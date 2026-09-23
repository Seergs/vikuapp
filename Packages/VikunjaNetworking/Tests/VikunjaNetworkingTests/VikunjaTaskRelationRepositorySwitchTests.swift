import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaTaskRelationRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyTaskRelationRepository()
        let v2 = SpyTaskRelationRepository()
        let capabilityProvider = FakeTaskRelationCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaTaskRelationRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        try await repository.addRelation(kind: .subtask, otherTaskID: 2, toTask: 1)

        #expect(v1.addRelationCallCount == 1)
        #expect(v2.addRelationCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyTaskRelationRepository()
        let v2 = SpyTaskRelationRepository()
        let capabilityProvider = FakeTaskRelationCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskRelationRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        try await repository.addRelation(kind: .subtask, otherTaskID: 2, toTask: 1)

        #expect(v1.addRelationCallCount == 0)
        #expect(v2.addRelationCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every method`() async throws {
        let v1 = SpyTaskRelationRepository()
        let v2 = SpyTaskRelationRepository()
        let capabilityProvider = FakeTaskRelationCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskRelationRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        try await repository.addRelation(kind: .subtask, otherTaskID: 2, toTask: 1)
        try await repository.removeRelation(kind: .blocked, otherTaskID: 3, fromTask: 1)

        #expect(v1.addRelationCallCount == 0)
        #expect(v1.removeRelationCallCount == 0)
        #expect(v2.addRelationCallCount == 1)
        #expect(v2.removeRelationCallCount == 1)
    }
}

private final class SpyTaskRelationRepository: TaskRelationRepositoryProtocol, @unchecked Sendable {
    private(set) var addRelationCallCount = 0
    private(set) var removeRelationCallCount = 0

    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        addRelationCallCount += 1
    }

    func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {
        removeRelationCallCount += 1
    }
}

private struct FakeTaskRelationCapabilityProvider: CapabilityProvider {
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
