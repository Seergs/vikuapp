import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaLabelRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyLabelRepository(label: "v1")
        let v2 = SpyLabelRepository(label: "v2")
        let capabilityProvider = FakeLabelCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaLabelRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let labels = try await repository.fetchLabels()

        #expect(labels.first?.title == "v1")
        #expect(v1.fetchLabelsCallCount == 1)
        #expect(v2.fetchLabelsCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyLabelRepository(label: "v1")
        let v2 = SpyLabelRepository(label: "v2")
        let capabilityProvider = FakeLabelCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaLabelRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let labels = try await repository.fetchLabels()

        #expect(labels.first?.title == "v2")
        #expect(v1.fetchLabelsCallCount == 0)
        #expect(v2.fetchLabelsCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every method`() async throws {
        let v1 = SpyLabelRepository(label: "v1")
        let v2 = SpyLabelRepository(label: "v2")
        let capabilityProvider = FakeLabelCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaLabelRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        _ = try await repository.create(Label(id: 0, title: "new", hexColor: "ffffff"))
        _ = try await repository.update(Label(id: 1, title: "renamed", hexColor: "ffffff"))
        try await repository.delete(id: 1)
        try await repository.addLabel(1, toTask: 1)
        try await repository.removeLabel(1, fromTask: 1)

        #expect(v1.createCallCount == 0)
        #expect(v1.updateCallCount == 0)
        #expect(v1.deleteCallCount == 0)
        #expect(v1.addLabelCallCount == 0)
        #expect(v1.removeLabelCallCount == 0)
        #expect(v2.createCallCount == 1)
        #expect(v2.updateCallCount == 1)
        #expect(v2.deleteCallCount == 1)
        #expect(v2.addLabelCallCount == 1)
        #expect(v2.removeLabelCallCount == 1)
    }
}

private final class SpyLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchLabelsCallCount = 0
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var addLabelCallCount = 0
    private(set) var removeLabelCallCount = 0

    init(label: String) {
        self.label = label
    }

    func fetchLabels() async throws -> [Label] {
        fetchLabelsCallCount += 1
        return [Label(id: 1, title: label, hexColor: "ffffff")]
    }

    func create(_ label: Label) async throws -> Label {
        createCallCount += 1
        return label
    }

    func update(_ label: Label) async throws -> Label {
        updateCallCount += 1
        return label
    }

    func delete(id: Int) async throws {
        deleteCallCount += 1
    }

    func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        addLabelCallCount += 1
    }

    func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        removeLabelCallCount += 1
    }
}

private struct FakeLabelCapabilityProvider: CapabilityProvider {
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
