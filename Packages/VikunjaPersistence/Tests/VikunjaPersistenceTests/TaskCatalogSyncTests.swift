import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct TaskCatalogSyncTests {
    @Test(arguments: [false, true])
    func `incomplete task download preserves cache queue and sync state until retry`(cancelled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 4, title: "Work")]
        let network = FakeTaskRepository()
        network.tasks = (1 ... 53).map { VikunjaTask(id: .remote($0), title: "Task \($0)", projectID: 4) }
        let engine = SyncEngine(
            localStore: store, projectRepository: projects, labelRepository: FakeLabelRepository(),
            taskRepository: network, relationRepository: FakeTaskRelationRepository(), accountID: accountID,
        )
        try await engine.pullProjects()
        try await engine.pullTasks()
        let repository = OfflineTaskRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        let created = try await repository.create(VikunjaTask(id: 0, title: "Created offline", projectID: 4))
        var edited = try await repository.fetchTask(id: .remote(52))
        edited.title = "Edited offline"
        _ = try await repository.update(edited)
        var conflicted = try await repository.fetchTask(id: .remote(53))
        conflicted.title = "Conflicting edit"
        _ = try await repository.update(conflicted)
        try await store.write { db in
            var item = try #require(MutationQueueRecord.fetchAll(db).last)
            item.needsConflictResolution = true
            try item.save(db)
        }
        let before = try await snapshot(store)

        network.fetchError = cancelled ? CancellationError() : VikunjaError.decoding("Incomplete paginated download")
        await #expect(throws: (any Error).self) { try await engine.pullTasks() }
        #expect(try await snapshot(store) == before)
        #expect(try await repository.fetchTasks(projectID: .remote(4)).count == 54)

        network.fetchError = nil
        network.tasks.append(VikunjaTask(id: 54, title: "Added on server", projectID: 4))
        try await engine.pullTasks()
        #expect(try await repository.fetchTasks(projectID: .remote(4)).count == 55)
        #expect(try await repository.fetchTask(id: .remote(52)).title == "Edited offline")
        #expect(try await repository.fetchTask(id: created.id).title == "Created offline")
        #expect(try await repository.fetchTask(id: .remote(54)).title == "Added on server")
        #expect(try await store.read { db in try MutationQueueRecord.fetchAll(db) } == before.mutations)
    }

    private struct Snapshot: Equatable, Sendable {
        let tasks: [TaskRecord]
        let mutations: [MutationQueueRecord]
        let syncState: [SyncStateRecord]
    }

    private func snapshot(_ store: LocalStore) async throws -> Snapshot {
        try await store.read { db in
            try Snapshot(
                tasks: TaskRecord.fetchAll(db), mutations: MutationQueueRecord.fetchAll(db),
                syncState: SyncStateRecord.fetchAll(db),
            )
        }
    }
}
