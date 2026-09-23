import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaProjectRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyProjectRepository(label: "v1")
        let v2 = SpyProjectRepository(label: "v2")
        let capabilityProvider = FakeCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaProjectRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let projects = try await repository.fetchProjects()

        #expect(projects.first?.title == "v1")
        #expect(v1.fetchProjectsCallCount == 1)
        #expect(v2.fetchProjectsCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyProjectRepository(label: "v1")
        let v2 = SpyProjectRepository(label: "v2")
        let capabilityProvider = FakeCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaProjectRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let projects = try await repository.fetchProjects()

        #expect(projects.first?.title == "v2")
        #expect(v1.fetchProjectsCallCount == 0)
        #expect(v2.fetchProjectsCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every method`() async throws {
        let v1 = SpyProjectRepository(label: "v1")
        let v2 = SpyProjectRepository(label: "v2")
        let capabilityProvider = FakeCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaProjectRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        _ = try await repository.fetchProject(id: 1)
        _ = try await repository.create(Project(id: 0, title: "new"))
        _ = try await repository.update(Project(id: 1, title: "renamed"))
        try await repository.delete(id: 1)

        #expect(v1.fetchProjectCallCount == 0)
        #expect(v1.createCallCount == 0)
        #expect(v1.updateCallCount == 0)
        #expect(v1.deleteCallCount == 0)
        #expect(v2.fetchProjectCallCount == 1)
        #expect(v2.createCallCount == 1)
        #expect(v2.updateCallCount == 1)
        #expect(v2.deleteCallCount == 1)
    }
}

private final class SpyProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchProjectsCallCount = 0
    private(set) var fetchProjectCallCount = 0
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    init(label: String) {
        self.label = label
    }

    func fetchProjects() async throws -> [Project] {
        fetchProjectsCallCount += 1
        return [Project(id: 1, title: label)]
    }

    func fetchProject(id: Int) async throws -> Project {
        fetchProjectCallCount += 1
        return Project(id: id, title: label)
    }

    func create(_ project: Project) async throws -> Project {
        createCallCount += 1
        return project
    }

    func update(_ project: Project) async throws -> Project {
        updateCallCount += 1
        return project
    }

    func delete(id: Int) async throws {
        deleteCallCount += 1
    }
}

private struct FakeCapabilityProvider: CapabilityProvider {
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
