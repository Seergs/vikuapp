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
        let user = try await AuthenticatedUserReader.fetch(client: client, token: tokenDTO.token, v2: true)
        return AuthSession(token: opaqueToken, user: user)
    }

    public func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        let user = try await AuthenticatedUserReader.fetch(client: client, token: token, v2: true)
        return AuthSession(token: token, user: user)
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
        let user = try await AuthenticatedUserReader.fetch(client: client, token: tokenDTO.token, v2: true)
        return AuthSession(token: opaqueToken, user: user)
    }

    public func logout() async {}
}
