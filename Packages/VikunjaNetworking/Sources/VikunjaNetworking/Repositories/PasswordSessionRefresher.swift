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

    private func refreshViaCookie(
        _ refreshToken: String,
        client: URLSessionAPIClient,
        baseURL: URL,
    ) async throws -> PasswordSessionCredential {
        let (dto, response): (AuthTokenDTO, HTTPURLResponse) = try await client.sendWithResponse(
            VikunjaEndpoints.userTokenRefresh(refreshToken: refreshToken),
        )
        let rotatedRefreshToken = HTTPCookie.cookies(
            withResponseHeaderFields: (response.allHeaderFields as? [String: String]) ?? [:],
            for: baseURL,
        ).first { $0.name == "vikunja_refresh_token" }?.value ?? refreshToken
        return PasswordSessionCredential(accessToken: dto.token, refreshToken: rotatedRefreshToken)
    }

    private func renewViaBearer(_ accessToken: String, baseURL: URL) async throws -> PasswordSessionCredential {
        let bearerClient = URLSessionAPIClient(baseURL: baseURL, session: session, authTokenProvider: { accessToken })
        let dto: AuthTokenDTO = try await bearerClient.send(VikunjaEndpoints.userTokenRenew())
        return PasswordSessionCredential(accessToken: dto.token, refreshToken: nil)
    }
}
