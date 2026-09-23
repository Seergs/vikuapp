import Foundation
import VikunjaCore

/// v2 implementation of `AuthServiceProtocol`. Identical shape to
/// `VikunjaAuthService` — see `VikunjaEndpoints.loginV2`/`oidcCallbackV2`'s
/// doc comments for the verification this rests on — just pointed at v2's
/// `/login` and OIDC callback paths.
public final class VikunjaAuthServiceV2: AuthServiceProtocol {
    private let client: APIClient
    private let baseURL: URL

    public init(client: APIClient, baseURL: URL) {
        self.client = client
        self.baseURL = baseURL
    }

    public func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        let (tokenDTO, response): (AuthTokenDTO, HTTPURLResponse) = try await client.sendWithResponse(
            VikunjaEndpoints.loginV2(credentials),
        )

        let refreshToken = HTTPCookie.cookies(
            withResponseHeaderFields: (response.allHeaderFields as? [String: String]) ?? [:],
            for: baseURL,
        ).first { $0.name == "vikunja_refresh_token" }?.value

        let sessionCredential = PasswordSessionCredential(accessToken: tokenDTO.token, refreshToken: refreshToken)
        let encoded = try JSONEncoder().encode(sessionCredential)
        let opaqueToken = String(data: encoded, encoding: .utf8) ?? ""
        return AuthSession(token: opaqueToken, user: User(id: 0, username: credentials.username))
    }

    public func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        AuthSession(token: token, user: User(id: 0, username: ""))
    }

    public func loginWithOIDC(provider: OIDCProvider, code: String, redirectURI: URL) async throws -> AuthSession {
        let (tokenDTO, response): (AuthTokenDTO, HTTPURLResponse) = try await client.sendWithResponse(
            VikunjaEndpoints.oidcCallbackV2(
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
        return AuthSession(token: opaqueToken, user: User(id: 0, username: ""))
    }

    public func logout() async {}
}
