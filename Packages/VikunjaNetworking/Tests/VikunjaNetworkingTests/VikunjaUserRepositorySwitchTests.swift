import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaUserRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyUserRepository(label: "v1")
        let v2 = SpyUserRepository(label: "v2")
        let capabilityProvider = FakeUserCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaUserRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let user = try await repository.fetchCurrentUser()

        #expect(user.username == "v1")
        #expect(v1.fetchCurrentUserCallCount == 1)
        #expect(v2.fetchCurrentUserCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyUserRepository(label: "v1")
        let v2 = SpyUserRepository(label: "v2")
        let capabilityProvider = FakeUserCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaUserRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let user = try await repository.fetchCurrentUser()

        #expect(user.username == "v2")
        #expect(v1.fetchCurrentUserCallCount == 0)
        #expect(v2.fetchCurrentUserCallCount == 1)
    }
}

private final class SpyUserRepository: UserRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchCurrentUserCallCount = 0

    init(label: String) {
        self.label = label
    }

    func fetchCurrentUser() async throws -> User {
        fetchCurrentUserCallCount += 1
        return User(id: 1, username: label)
    }
}

private struct FakeUserCapabilityProvider: CapabilityProvider {
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
