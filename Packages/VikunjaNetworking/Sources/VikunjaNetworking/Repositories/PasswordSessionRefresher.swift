import Foundation
import VikunjaCore

/// Resolves a currently-valid bearer credential for any saved account,
/// transparently refreshing a password- or OIDC-based session's JWT before
/// it expires. Drop-in replacement for `AccountStoreProtocol.token
/// (forAccountID:)` inside every `tokenProvider` closure — an API-token
/// account passes straight through with no behavior change; a password or
/// OIDC account's stored credential (an opaque, JSON-encoded
/// `PasswordSessionCredential` — the same shape either way, since Vikunja
/// issues an identical JWT/refresh-cookie session regardless of which login
/// method produced it) is decoded, checked against its JWT's `exp`, and
/// refreshed via whichever of Vikunja's two renewal endpoints its server
/// actually supports (detected from whether a refresh token was captured at
/// login — see `VikunjaAuthService`).
///
/// Refresh is single-flighted per account: concurrent callers for the same
/// account await the same in-progress attempt instead of racing duplicate
/// refresh calls (a real risk once a refresh token rotates on use).
public actor PasswordSessionRefresher {
    /// Refresh is attempted once the access token has less than this much
    /// time left, so a request doesn't get built with a token that expires
    /// mid-flight.
    private static let refreshMargin: TimeInterval = 60

    private let accountStore: AccountStoreProtocol
    private let session: URLSession
    private let cancelRefreshOnCancellation: Bool
    /// Notified the moment a refresh is found to be unrecoverable — `nil` in
    /// contexts with no UI to react to it (the widget extension).
    private let sessionExpiryReporter: SessionExpiryReporting?
    private var inFlight: [InstanceAccount.ID: Task<Result<String?, Error>, Never>] = [:]

    public init(
        accountStore: AccountStoreProtocol,
        session: URLSession = .vikunjaDefault,
        sessionExpiryReporter: SessionExpiryReporting? = nil,
        cancelRefreshOnCancellation: Bool = false,
    ) {
        self.accountStore = accountStore
        self.session = session
        self.sessionExpiryReporter = sessionExpiryReporter
        self.cancelRefreshOnCancellation = cancelRefreshOnCancellation
    }

    private struct SessionReplaced: Error {}

    /// - Throws: `VikunjaError.sessionExpired` when this account's session
    ///   was already flagged unrecoverable (short-circuits without a network
    ///   call — a refresh attempt would only fail the same way again) or
    ///   when a refresh attempted just now is rejected outright. Any other
    ///   failure (network hiccup, a flaky server response) is transient and
    ///   falls back to the stale stored token instead of throwing, so a
    ///   momentary connectivity blip doesn't force a re-login.
    public func validToken(for account: InstanceAccount) async throws -> String? {
        while true {
            guard let current = try await accountStore.fetchAccounts().first(where: { $0.id == account.id }),
                  let stored = try await accountStore.token(forAccountID: account.id) else { return nil }
            try account.validateIdentity(of: current)
            guard current.authMethod != .apiToken else { return stored }
            guard !current.needsReauthentication else { throw VikunjaError.sessionExpired }
            guard let credential = try? JSONDecoder().decode(
                PasswordSessionCredential.self, from: Data(stored.utf8),
            ) else { return nil }
            if let expiry = JWTExpiryReader.expiry(of: credential.accessToken),
               expiry.timeIntervalSinceNow > Self.refreshMargin {
                return credential.accessToken
            }
            do {
                return try await coordinatedRefresh(account: current, credential: credential, stored: stored)
            } catch is SessionReplaced {
                // A login replaced this attempt while its response was in flight.
                // Resolve the current session after leaving the old single flight.
                try Task.checkCancellation()
            }
        }
    }

    /// Resolve renewal before taking the snapshot used to bind legacy identity.
    /// The lookup uses that exact bearer, and a concurrent login still invalidates its result.
    public func currentUser(
        for account: InstanceAccount,
        fetching fetchUser: @Sendable (String) async throws -> User,
    ) async throws -> User {
        guard let bearer = try await validToken(for: account),
              let current = try await accountStore.fetchAccounts().first(where: { $0.id == account.id }),
              let stored = try await accountStore.token(forAccountID: account.id) else {
            throw VikunjaError.unauthorized
        }
        try account.validateIdentity(of: current)
        let storedBearer = current.authMethod == .apiToken ? stored : (try? JSONDecoder().decode(
            PasswordSessionCredential.self, from: Data(stored.utf8),
        ))?.accessToken
        guard storedBearer == bearer else { throw ConnectionIdentityError.sessionChanged }
        let user = try await fetchUser(bearer)
        try Task.checkCancellation()
        guard user.id > 0 else { throw ConnectionIdentityError.unverifiedUser }
        if let userID = current.userID, userID != user.id {
            throw ConnectionIdentityError.userChanged
        }
        var bound = current
        bound.userID = user.id
        bound.username = user.username
        if bound != current {
            try await accountStore.replaceSession(bound, token: stored, expected: current, matchingToken: stored)
        } else {
            guard try await accountStore.fetchAccounts().contains(current),
                  try await accountStore.token(forAccountID: current.id) == stored else {
                throw ConnectionIdentityError.sessionChanged
            }
        }
        return user
    }

    private func coordinatedRefresh(
        account: InstanceAccount,
        credential: PasswordSessionCredential,
        stored: String,
    ) async throws -> String? {
        if let existing = inFlight[account.id] {
            return try await awaitRefresh(existing)
        }
        let task = Task { await self.performRefresh(account: account, credential: credential, stored: stored) }
        inFlight[account.id] = task
        defer { inFlight[account.id] = nil }
        return try await awaitRefresh(task)
    }

    /// The app preserves shared renewals when a screen disappears. A widget's
    /// single coordinator opts in so its execution deadline also stops renewal.
    private func awaitRefresh(_ task: Task<Result<String?, Error>, Never>) async throws -> String? {
        let cancelRefresh = cancelRefreshOnCancellation
        return try await withTaskCancellationHandler {
            let result = await task.value
            try Task.checkCancellation()
            return try result.get()
        } onCancel: {
            if cancelRefresh {
                task.cancel()
            }
        }
    }

    /// Falls back to the stale stored token on a transient failure (network
    /// hiccup, a flaky non-auth server error) — the caller that ultimately
    /// makes a request with it will get a normal 401 that surfaces as
    /// `VikunjaError.unauthorized`, exactly like a revoked API token does
    /// today. A refresh rejected outright (`.unauthorized` from the refresh
    /// endpoint itself) means the session can't be renewed at all: that's
    /// persisted onto the account and reported, so callers get
    /// `.sessionExpired` instead of endlessly retrying a doomed token.
    private func performRefresh(
        account: InstanceAccount,
        credential: PasswordSessionCredential,
        stored: String,
    ) async -> Result<String?, Error> {
        let client = URLSessionAPIClient(baseURL: account.baseURL, session: session)
        do {
            let updated: PasswordSessionCredential = if let refreshToken = credential.refreshToken {
                try await refreshViaCookie(refreshToken, client: client, baseURL: account.baseURL)
            } else {
                try await renewViaBearer(credential.accessToken, baseURL: account.baseURL)
            }
            // A confirmed rotation must be saved even if the caller just
            // cancelled; dropping it would strand the previous refresh token.
            let encodedData = try JSONEncoder().encode(updated)
            let encoded = String(data: encodedData, encoding: .utf8) ?? ""
            guard try await accountStore.updateSession(
                for: account, matchingToken: stored, token: encoded, needsReauthentication: false,
            ) else { return .failure(SessionReplaced()) }
            return .success(updated.accessToken)
        } catch VikunjaError.unauthorized {
            if Task.isCancelled {
                return .failure(CancellationError())
            }
            do {
                guard try await accountStore.updateSession(
                    for: account, matchingToken: stored, token: nil, needsReauthentication: true,
                ) else { return .failure(SessionReplaced()) }
                await sessionExpiryReporter?.reportSessionExpired(accountID: account.id)
                return .failure(VikunjaError.sessionExpired)
            } catch {
                return .failure(error)
            }
        } catch {
            if Task.isCancelled {
                return .failure(CancellationError())
            }
            guard await (try? accountStore.token(forAccountID: account.id)) == stored else {
                return .failure(SessionReplaced())
            }
            return .success(credential.accessToken)
        }
    }

    /// `/user/token/refresh` keeps its v1 meaning in v2 (see
    /// `VikunjaEndpoints.userTokenRefreshV2`'s doc comment), so this checks
    /// capability per call — same lazy, cache-backed pattern as every
    /// resource switch, just inlined here since this method (not a whole
    /// repository) is the only v1/v2-sensitive call site in this type.
    private func refreshViaCookie(
        _ refreshToken: String,
        client: URLSessionAPIClient,
        baseURL: URL,
    ) async throws -> PasswordSessionCredential {
        let supportsV2 = await VikunjaCapabilityProvider(client: client).supports(.apiV2)
        let endpoint = supportsV2
            ? VikunjaEndpoints.userTokenRefreshV2(refreshToken: refreshToken)
            : VikunjaEndpoints.userTokenRefresh(refreshToken: refreshToken)
        let (dto, response): (AuthTokenDTO, HTTPURLResponse) = try await client.sendWithResponse(endpoint)
        let rotatedRefreshToken = HTTPCookie.cookies(
            withResponseHeaderFields: (response.allHeaderFields as? [String: String]) ?? [:],
            for: baseURL,
        ).first { $0.name == "vikunja_refresh_token" }?.value ?? refreshToken
        return PasswordSessionCredential(accessToken: dto.token, refreshToken: rotatedRefreshToken)
    }

    /// v1 only, deliberately: this renews a user's session JWT via bearer
    /// when no refresh token was ever captured — i.e. a pre-2.0 server
    /// (see `VikunjaAuthService.login(_:)`'s doc comment). v2 requires
    /// 2.4.0+, which is always well past 2.0 and therefore always sets a
    /// refresh-token cookie at login, so this branch is unreachable for any
    /// account this app would ever route to v2 — and v2 has no equivalent
    /// endpoint for it anyway (`/user/token` is narrowed to link-share
    /// tokens only in v2, see `VikunjaEndpoints.userTokenRefreshV2`'s doc
    /// comment).
    private func renewViaBearer(_ accessToken: String, baseURL: URL) async throws -> PasswordSessionCredential {
        let bearerClient = URLSessionAPIClient(baseURL: baseURL, session: session, authTokenProvider: { accessToken })
        let dto: AuthTokenDTO = try await bearerClient.send(VikunjaEndpoints.userTokenRenew())
        return PasswordSessionCredential(accessToken: dto.token, refreshToken: nil)
    }
}
