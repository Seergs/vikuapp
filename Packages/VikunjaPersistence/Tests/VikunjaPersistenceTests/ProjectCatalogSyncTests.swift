import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct ProjectCatalogSyncTests {
    @Test
    func `complete catalog removes a remotely deleted project before task downloads`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let network = FakeProjectRepository()
        network.projects = [Project(id: 72, title: "Deleted remotely"), Project(id: 73, title: "Remaining")]
        let tasks = FakeTaskRepository()
        tasks.tasks = [VikunjaTask(id: 1, title: "Deleted project's task", projectID: 72)]
        let engine = SyncEngine(
            localStore: store, projectRepository: network, labelRepository: FakeLabelRepository(),
            taskRepository: tasks, relationRepository: FakeTaskRelationRepository(), accountID: accountID,
        )
        try await engine.pullProjects()
        try await engine.pullTasks()
        #expect(tasks.fetchTasksCallCount == 2)

        network.projects = [Project(id: 73, title: "Remaining")]
        tasks.fetchErrorsByProjectID[72] = VikunjaError.notFound
        try await engine.pullProjects()
        try await engine.pullTasks()

        #expect(tasks.fetchTasksCallCount == 3)
        let repository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await repository.fetchProjects().map(\.id) == [.remote(73)])
        #expect(try await store.read { db in try TaskRecord.fetchAll(db).isEmpty })
    }

    @Test(arguments: [false, true])
    func `failed project catalog preserves offline hierarchy and pending edits until retry`(cancelled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let network = FakeProjectRepository()
        // The parent is in a later page's portion of the complete catalog.
        network.projects = (1 ... 60).map { id in
            Project(id: .remote(id), title: "Project \(id)", parentProjectID: id == 60 ? nil : .remote(60))
        }
        network.projects += [Project(id: -1, title: "Favorites"), Project(id: -8, title: "Saved filter")]
        let tasks = FakeTaskRepository()
        tasks.tasks = [VikunjaTask(id: 1, title: "Cached task", projectID: 59)]
        let engine = SyncEngine(
            localStore: store, projectRepository: network, labelRepository: FakeLabelRepository(),
            taskRepository: tasks, relationRepository: FakeTaskRelationRepository(), accountID: accountID,
        )
        try await engine.pullProjects()
        try await engine.pullTasks()
        let repository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        let offlineTasks = OfflineTaskRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await repository.fetchProjects().count == 62)
        #expect(try await repository.fetchProject(id: .remote(1)).parentProjectID == .remote(60))
        #expect(try await repository.fetchProject(id: .remote(-8)).savedFilterID == 7)
        #expect(try await offlineTasks.fetchTasks(projectID: .remote(59)).map(\.title) == ["Cached task"])

        let created = try await repository.create(
            Project(id: 0, title: "Created offline", parentProjectID: .remote(60)),
        )
        _ = try await repository.update(Project(id: 59, title: "Edited offline", parentProjectID: .remote(60)))
        let before = try await snapshot(store)

        // Networking must throw for a later-page failure instead of returning a partial catalog.
        network.fetchError = cancelled ? CancellationError() : VikunjaError.offline
        await #expect(throws: (any Error).self) { try await engine.pullProjects() }
        #expect(try await snapshot(store) == before)
        #expect(try await repository.fetchProjects().count == 63)

        network.fetchError = nil
        network.projects.append(Project(id: 61, title: "Added on server", parentProjectID: .remote(60)))
        try await engine.pullProjects()
        let recovered = try await repository.fetchProjects()
        #expect(recovered.count == 64)
        #expect(recovered.contains { $0.id == .remote(61) && $0.parentProjectID == .remote(60) })
        #expect(recovered.contains { $0.id == .remote(59) && $0.title == "Edited offline" })
        #expect(recovered.contains { $0.id == created.id && $0.parentProjectID == .remote(60) })
        #expect(try await offlineTasks.fetchTasks(projectID: .remote(59)).map(\.title) == ["Cached task"])
        #expect(try await store.read { db in try MutationQueueRecord.fetchAll(db) } == before.mutations)
    }

    private struct Snapshot: Equatable, Sendable {
        let projects: [ProjectRecord]
        let tasks: [TaskRecord]
        let filters: [SavedFilterRecord]
        let mutations: [MutationQueueRecord]
        let syncState: [SyncStateRecord]
    }

    private func snapshot(_ store: LocalStore) async throws -> Snapshot {
        try await store.read { db in
            try Snapshot(
                projects: ProjectRecord.fetchAll(db), tasks: TaskRecord.fetchAll(db),
                filters: SavedFilterRecord.fetchAll(db), mutations: MutationQueueRecord.fetchAll(db),
                syncState: SyncStateRecord.fetchAll(db),
            )
        }
    }
}
