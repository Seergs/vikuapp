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
    private var inFlight: [InstanceAccount.ID: Task<String?, Never>] = [:]

    public init(accountStore: AccountStoreProtocol, session: URLSession = .shared) {
        self.accountStore = accountStore
        self.session = session
    }

    public func validToken(for account: InstanceAccount) async -> String? {
        guard account.authMethod != .apiToken else {
            return try? await accountStore.token(forAccountID: account.id)
        }
        guard let stored = try? await accountStore.token(forAccountID: account.id),
              let credential = try? JSONDecoder().decode(PasswordSessionCredential.self, from: Data(stored.utf8))
        else {
            return nil
        }

        if let expiry = JWTExpiryReader.expiry(of: credential.accessToken),
           expiry.timeIntervalSinceNow > Self.refreshMargin {
            return credential.accessToken
        }
        return await coordinatedRefresh(account: account, credential: credential)
    }

    private func coordinatedRefresh(account: InstanceAccount, credential: PasswordSessionCredential) async -> String? {
        if let existing = inFlight[account.id] {
            return await existing.value
        }
        let task = Task { await self.performRefresh(account: account, credential: credential) }
        inFlight[account.id] = task
        defer { inFlight[account.id] = nil }
        return await task.value
    }

    /// Falls back to the stale stored token on any failure (network hiccup,
    /// revoked session) rather than surfacing an error here — the caller
    /// that ultimately makes a request with it will get a normal 401 that
    /// surfaces as `VikunjaError.unauthorized`, exactly like a revoked API
    /// token does today.
    private func performRefresh(account: InstanceAccount, credential: PasswordSessionCredential) async -> String? {
        let client = URLSessionAPIClient(baseURL: account.baseURL, session: session)
        do {
            let updated: PasswordSessionCredential = if let refreshToken = credential.refreshToken {
                try await refreshViaCookie(refreshToken, client: client, baseURL: account.baseURL)
            } else {
                try await renewViaBearer(credential.accessToken, baseURL: account.baseURL)
            }
            let encodedData = try JSONEncoder().encode(updated)
            let encoded = String(data: encodedData, encoding: .utf8) ?? ""
            try? await accountStore.updateAccount(account, token: encoded)
            return updated.accessToken
        } catch {
            return credential.accessToken
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
