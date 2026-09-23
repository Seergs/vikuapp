import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaTaskRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyTaskRepository(label: "v1")
        let v2 = SpyTaskRepository(label: "v2")
        let capabilityProvider = FakeTaskCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaTaskRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let tasks = try await repository.fetchTasks(projectID: 1)

        #expect(tasks.first?.title == "v1")
        #expect(v1.fetchTasksCallCount == 1)
        #expect(v2.fetchTasksCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyTaskRepository(label: "v1")
        let v2 = SpyTaskRepository(label: "v2")
        let capabilityProvider = FakeTaskCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let tasks = try await repository.fetchTasks(projectID: 1)

        #expect(tasks.first?.title == "v2")
        #expect(v1.fetchTasksCallCount == 0)
        #expect(v2.fetchTasksCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every method`() async throws {
        let v1 = SpyTaskRepository(label: "v1")
        let v2 = SpyTaskRepository(label: "v2")
        let capabilityProvider = FakeTaskCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        _ = try await repository.fetchTask(id: 1)
        _ = try await repository.create(VikunjaTask(id: 0, title: "new", projectID: 1))
        _ = try await repository.update(VikunjaTask(id: 1, title: "renamed", projectID: 1))
        try await repository.delete(id: 1)
        _ = try await repository.searchTasks(query: "coffee")

        #expect(v1.fetchTaskCallCount == 0)
        #expect(v1.createCallCount == 0)
        #expect(v1.updateCallCount == 0)
        #expect(v1.deleteCallCount == 0)
        #expect(v1.searchTasksCallCount == 0)
        #expect(v2.fetchTaskCallCount == 1)
        #expect(v2.createCallCount == 1)
        #expect(v2.updateCallCount == 1)
        #expect(v2.deleteCallCount == 1)
        #expect(v2.searchTasksCallCount == 1)
    }
}

private final class SpyTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchTasksCallCount = 0
    private(set) var fetchTaskCallCount = 0
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var searchTasksCallCount = 0

    init(label: String) {
        self.label = label
    }

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        fetchTasksCallCount += 1
        return [VikunjaTask(id: 1, title: label, projectID: projectID)]
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        fetchTaskCallCount += 1
        return VikunjaTask(id: id, title: label, projectID: 1)
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        createCallCount += 1
        return task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        updateCallCount += 1
        return task
    }

    func delete(id: Int) async throws {
        deleteCallCount += 1
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        searchTasksCallCount += 1
        return [VikunjaTask(id: 1, title: label, projectID: 1)]
    }
}

private struct FakeTaskCapabilityProvider: CapabilityProvider {
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
