import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaAuthServiceSwitchTests {
    private static let oidcProvider = OIDCProvider(
        key: "authentik",
        name: "Authentik",
        authURL: URL(string: "https://auth.example.com/o/authorize/")!,
        clientID: "vikunja-client-id",
        scope: "openid email profile",
    )

    @Test
    func `delegates login to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyAuthService(label: "v1")
        let v2 = SpyAuthService(label: "v2")
        let capabilityProvider = FakeAuthCapabilityProvider(supportsAPIV2: false)
        let service = VikunjaAuthServiceSwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let session = try await service.login(LoginCredentials(username: "sergio", password: "hunter2"))

        #expect(session.token == "v1")
        #expect(v1.loginCallCount == 1)
        #expect(v2.loginCallCount == 0)
    }

    @Test
    func `delegates login to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyAuthService(label: "v1")
        let v2 = SpyAuthService(label: "v2")
        let capabilityProvider = FakeAuthCapabilityProvider(supportsAPIV2: true)
        let service = VikunjaAuthServiceSwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let session = try await service.login(LoginCredentials(username: "sergio", password: "hunter2"))

        #expect(session.token == "v2")
        #expect(v1.loginCallCount == 0)
        #expect(v2.loginCallCount == 1)
    }

    @Test
    func `delegates loginWithOIDC based on capability too`() async throws {
        let v1 = SpyAuthService(label: "v1")
        let v2 = SpyAuthService(label: "v2")
        let capabilityProvider = FakeAuthCapabilityProvider(supportsAPIV2: true)
        let service = VikunjaAuthServiceSwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)
        let redirectURI = try #require(URL(string: "viku://oidc-callback"))

        _ = try await service.loginWithOIDC(provider: Self.oidcProvider, code: "auth-code", redirectURI: redirectURI)

        #expect(v1.loginWithOIDCCallCount == 0)
        #expect(v2.loginWithOIDCCallCount == 1)
    }

    @Test
    func `loginWithAPIToken AND logout never touch either service`() async throws {
        let v1 = SpyAuthService(label: "v1")
        let v2 = SpyAuthService(label: "v2")
        let capabilityProvider = FakeAuthCapabilityProvider(supportsAPIV2: true)
        let service = VikunjaAuthServiceSwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let session = try await service.loginWithAPIToken("raw-token")
        await service.logout()

        #expect(session.token == "raw-token")
        #expect(v1.loginWithAPITokenCallCount == 0)
        #expect(v1.logoutCallCount == 0)
        #expect(v2.loginWithAPITokenCallCount == 0)
        #expect(v2.logoutCallCount == 0)
    }
}

private final class SpyAuthService: AuthServiceProtocol, @unchecked Sendable {
    let label: String
    private(set) var loginCallCount = 0
    private(set) var loginWithAPITokenCallCount = 0
    private(set) var loginWithOIDCCallCount = 0
    private(set) var logoutCallCount = 0

    init(label: String) {
        self.label = label
    }

    func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        loginCallCount += 1
        return AuthSession(token: label, user: User(id: 1, username: credentials.username))
    }

    func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        loginWithAPITokenCallCount += 1
        return AuthSession(token: token, user: User(id: 1, username: ""))
    }

    func loginWithOIDC(provider: OIDCProvider, code: String, redirectURI: URL) async throws -> AuthSession {
        loginWithOIDCCallCount += 1
        return AuthSession(token: label, user: User(id: 1, username: ""))
    }

    func logout() async {
        logoutCallCount += 1
    }
}

private struct FakeAuthCapabilityProvider: CapabilityProvider {
    let supportsAPIV2: Bool

    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "2.4.0", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        switch feature {
        case .apiV2:
            supportsAPIV2
        default:
            false
        }
    }
}
