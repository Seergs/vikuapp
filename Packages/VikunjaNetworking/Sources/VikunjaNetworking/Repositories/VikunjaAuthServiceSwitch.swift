import Foundation
import VikunjaCore

/// Routes `login(_:)`/`loginWithOIDC(...)` to the v1 or v2 concrete service
/// based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, applied here to `AuthServiceProtocol` instead of a
/// `Repositories/` type since login is the one thing
/// `InstanceClientFactoryProtocol` builds without a resource protocol).
/// `loginWithAPIToken(_:)`/`logout()` touch no endpoint either version
/// changed, so this implements them directly rather than routing.
final class VikunjaAuthServiceSwitch: AuthServiceProtocol {
    private let v1: AuthServiceProtocol
    private let v2: AuthServiceProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: AuthServiceProtocol, v2: AuthServiceProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> AuthServiceProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        try await resolve().login(credentials)
    }

    func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        AuthSession(token: token, user: User(id: 0, username: ""))
    }

    func loginWithOIDC(provider: OIDCProvider, code: String, redirectURI: URL) async throws -> AuthSession {
        try await resolve().loginWithOIDC(provider: provider, code: code, redirectURI: redirectURI)
    }

    func logout() async {}
}
