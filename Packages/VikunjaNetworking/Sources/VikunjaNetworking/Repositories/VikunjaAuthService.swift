import Foundation
import VikunjaCore

/// Implements login against `/api/v1/login`. Persisting the token (Keychain,
/// multi-account) is `VikuAuth`'s responsibility — this service only knows
/// how to talk to the endpoint.
public final class VikunjaAuthService: AuthServiceProtocol {
    private let client: APIClient
    private let baseURL: URL

    public init(client: APIClient, baseURL: URL) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Login returns the JWT; a separate candidate-authenticated user read establishes identity.
    ///
    /// The returned `AuthSession.token` is an opaque, JSON-encoded
    /// `PasswordSessionCredential` — not the raw JWT — carrying a refresh
    /// token too when the server sets one (a v2.0+ instance's
    /// `vikunja_refresh_token` cookie). Callers must only pass it through to
    /// `AccountStoreProtocol`, never parse it.
    public func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        let (tokenDTO, response): (AuthTokenDTO, HTTPURLResponse) = try await client.sendWithResponse(
            VikunjaEndpoints.login(credentials),
        )

        let refreshToken = HTTPCookie.cookies(
            withResponseHeaderFields: (response.allHeaderFields as? [String: String]) ?? [:],
            for: baseURL,
        ).first { $0.name == "vikunja_refresh_token" }?.value

        let sessionCredential = PasswordSessionCredential(accessToken: tokenDTO.token, refreshToken: refreshToken)
        let encoded = try JSONEncoder().encode(sessionCredential)
        let opaqueToken = String(data: encoded, encoding: .utf8) ?? ""
        let user = try await AuthenticatedUserReader.fetch(client: client, token: tokenDTO.token, v2: false)
        return AuthSession(token: opaqueToken, user: user)
    }

    public func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        let user = try await AuthenticatedUserReader.fetch(client: client, token: token, v2: false)
        return AuthSession(token: token, user: user)
    }

    /// Same opaque-credential handling as `login(_:)` — see its doc comment.
    public func loginWithOIDC(provider: OIDCProvider, code: String, redirectURI: URL) async throws -> AuthSession {
        let (tokenDTO, response): (AuthTokenDTO, HTTPURLResponse) = try await client.sendWithResponse(
            VikunjaEndpoints.oidcCallback(
                providerKey: provider.key,
                code: code,
                scope: provider.scope,
                redirectURL: redirectURI,
            ),
        )

        let refreshToken = HTTPCookie.cookies(
            withResponseHeaderFields: (response.allHeaderFields as? [String: String]) ?? [:],
            for: baseURL,
        ).first { $0.name == "vikunja_refresh_token" }?.value

        let sessionCredential = PasswordSessionCredential(accessToken: tokenDTO.token, refreshToken: refreshToken)
        let encoded = try JSONEncoder().encode(sessionCredential)
        let opaqueToken = String(data: encoded, encoding: .utf8) ?? ""
        let user = try await AuthenticatedUserReader.fetch(client: client, token: tokenDTO.token, v2: false)
        return AuthSession(token: opaqueToken, user: user)
    }

    public func logout() async {}
}
