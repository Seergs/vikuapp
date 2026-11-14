import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct TaskRelationDeletionTests {
    private struct Fixture {
        let store: LocalStore
        let accountID: UUID
        let project: ProjectRecord
        let first: TaskRecord
        let second: TaskRecord
        let tasks: OfflineTaskRepository
        let relations: OfflineTaskRelationRepository
        let remoteTasks: FakeTaskRepository
        let remoteRelations: FakeTaskRelationRepository
        let engine: SyncEngine
    }

    private func fixture(localSecond: Bool = false) async throws -> Fixture {
        let store = try LocalStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        let accountID = UUID()
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Project", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0,
            hexColor: "", serverUpdatedAt: nil,
        )
        let first = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: 5, title: "First", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID, serverUpdatedAt: nil,
        )
        var second = first
        second.localID = UUID()
        second.remoteID = localSecond ? nil : 6
        second.title = "Second"
        let secondRow = second
        try await store.write { db in
            try project.insert(db)
            try first.insert(db)
            try secondRow.insert(db)
        }
        let remoteTasks = FakeTaskRepository()
        let remoteRelations = FakeTaskRelationRepository()
        return Fixture(
            store: store, accountID: accountID, project: project, first: first, second: secondRow,
            tasks: OfflineTaskRepository(
                localStore: store,
                accountID: accountID,
                syncRequester: NoopKanbanSyncRequester(),
            ),
            relations: OfflineTaskRelationRepository(
                localStore: store,
                accountID: accountID,
                syncRequester: NoopKanbanSyncRequester(),
            ),
            remoteTasks: remoteTasks, remoteRelations: remoteRelations,
            engine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
                taskRepository: remoteTasks, relationRepository: remoteRelations, accountID: accountID,
            ),
        )
    }

    private func confirmRelation(_ fixture: Fixture, kind: RelationKind = .subtask) async throws {
        try await fixture.relations.addRelation(kind: kind, otherTaskID: .remote(6), toTask: .remote(5))
        try await fixture.engine.drainTaskMutations()
    }

    @Test(arguments: [false, true], RelationKind.allCases)
    func `confirmed relations disappear immediately from either endpoint and remain absent after sync`(
        deleteFirst: Bool, kind: RelationKind,
    ) async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture, kind: kind)
        let deletedID = EntityID.remote(deleteFirst ? 5 : 6)
        let survivorID = EntityID.remote(deleteFirst ? 6 : 5)
        try await fixture.tasks.delete(id: deletedID)
        let survivor = try await fixture.tasks.fetchTask(id: survivorID)
        #expect(survivor.subtasks.isEmpty && !survivor.hasRelations)
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 2)
        await #expect(throws: VikunjaError.notFound) { try await fixture.tasks.fetchTask(id: deletedID) }
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 0)
        let reloaded = try await fixture.tasks.fetchTask(id: survivorID)
        #expect(reloaded.subtasks.isEmpty && !reloaded.hasRelations)
    }

    @Test
    func `failed deletion keeps relations hidden and retry performs final cleanup`() async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture)
        fixture.remoteTasks.deleteError = VikunjaError.offline
        try await fixture.tasks.delete(id: .remote(6))
        await #expect(throws: VikunjaError.offline) { try await fixture.engine.drainTaskMutations() }
        #expect(try await fixture.tasks.fetchTask(id: .remote(5)).subtasks.isEmpty)
        fixture.remoteTasks.deleteError = VikunjaError.notFound
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 0)
    }

    @Test
    func `server rejection preserves confirmed and pending relations for recovery`() async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture)
        try await fixture.relations.addRelation(kind: .related, otherTaskID: .remote(6), toTask: .remote(5))
        try await fixture.tasks.delete(id: .remote(6))
        fixture.remoteTasks.deleteError = VikunjaError.unauthorized
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remoteRelations.addedRelations.count == 1)
        #expect(try await fixture.tasks.fetchTask(id: .remote(5)).subtasks.isEmpty)
        // Simulate removal of the failed delete intent; its cached relation state remains recoverable.
        try await fixture.store.write { db in
            try MutationQueueRecord.filter(Column("operation") == "delete").deleteAll(db)
        }
        let restored = try await fixture.tasks.fetchTask(id: .remote(5))
        #expect(restored.subtasks.map(\.id) == [.remote(6)])
        #expect(restored.otherRelations[.related]?.map(\.id) == [.remote(6)])
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remoteRelations.addedRelations.count == 2)
    }

    @Test(arguments: [false, true], [false, true])
    func `pending relations in either direction are removed when either local or remote target is deleted`(
        localSecond: Bool, reverse: Bool,
    ) async throws {
        let fixture = try await fixture(localSecond: localSecond)
        let secondID = fixture.second.remoteID.map(EntityID.remote) ?? .local(fixture.second.localID)
        try await fixture.relations.addRelation(
            kind: .related, otherTaskID: reverse ? .remote(5) : secondID,
            toTask: reverse ? secondID : .remote(5),
        )
        try await fixture.tasks.delete(id: secondID)
        let survivor = try await fixture.tasks.fetchTask(id: .remote(5))
        #expect(survivor.otherRelations.isEmpty)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remoteRelations.addedRelations.isEmpty)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `new relation commands reject endpoints pending deletion`() async throws {
        let fixture = try await fixture()
        try await fixture.tasks.delete(id: .remote(6))
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.relations.addRelation(kind: .related, otherTaskID: .remote(6), toTask: .remote(5))
        }
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.relations.removeRelation(kind: .related, otherTaskID: .remote(5), fromTask: .remote(6))
        }
    }

    @Test
    func `late relation response cannot restore references after a confirmed deletion`() async throws {
        let fixture = try await fixture()
        fixture.remoteRelations.beforeAddResponse = {
            try await fixture.store.write { db in
                try db.execute(sql: "UPDATE mutationQueueItem SET status = 'inFlight' WHERE operation = 'addRelation'")
            }
            try await fixture.tasks.delete(id: .remote(6))
            try await fixture.engine.drainTaskMutations()
        }
        try await fixture.relations.addRelation(kind: .related, otherTaskID: .remote(6), toTask: .remote(5))
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `late relation response stays hidden during a pending deletion`() async throws {
        let fixture = try await fixture()
        fixture.remoteRelations.beforeAddResponse = { try await fixture.tasks.delete(id: .remote(6)) }
        try await fixture.relations.addRelation(kind: .related, otherTaskID: .remote(6), toTask: .remote(5))
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.tasks.fetchTask(id: .remote(5)).otherRelations.isEmpty)
        fixture.remoteRelations.beforeAddResponse = nil
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 0)
    }

    @Test
    func `deletion cleanup is isolated to the account and preserves uncached relation targets`() async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture)
        let otherAccount = UUID()
        var project = fixture.project
        project.localID = UUID()
        project.accountID = otherAccount
        var task = fixture.first
        task.localID = UUID()
        task.accountID = otherAccount
        task.projectLocalID = project.localID
        let otherProject = project
        let otherTask = task
        try await fixture.store.write { db in
            try otherProject.insert(db)
            try otherTask.insert(db)
            try TaskRelationRecord(
                localID: UUID(),
                accountID: otherAccount,
                taskLocalID: otherTask.localID,
                kind: .related,
                otherTaskRemoteID: 6,
                otherProjectRemoteID: 1,
                title: "Other account",
                isDone: false,
            ).insert(db)
            try TaskRelationRecord(
                localID: UUID(),
                accountID: fixture.accountID,
                taskLocalID: fixture.first.localID,
                kind: .related,
                otherTaskRemoteID: 99,
                otherProjectRemoteID: 2,
                title: "Not downloaded",
                isDone: false,
            ).insert(db)
        }
        try await fixture.tasks.delete(id: .remote(6))
        try await fixture.engine.drainTaskMutations()
        let survivor = try await fixture.tasks.fetchTask(id: .remote(5))
        #expect(survivor.otherRelations[.related]?.map(\.id) == [.remote(99)])
        let otherTasks = OfflineTaskRepository(
            localStore: fixture.store,
            accountID: otherAccount,
            syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await otherTasks.fetchTask(id: .remote(5)).otherRelations[.related]?.map(\.id) == [.remote(6)])
    }

    @Test
    func `remote deletion refresh replaces the surviving tasks relations`() async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture)
        fixture.remoteTasks.tasks = [VikunjaTask(id: .remote(5), title: "First", projectID: .remote(1))]
        try await fixture.engine.pullTasks()
        #expect(try await fixture.tasks.fetchTask(id: .remote(5)).subtasks.isEmpty)
        await #expect(throws: VikunjaError.notFound) { try await fixture.tasks.fetchTask(id: .remote(6)) }
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 0)
    }

    @Test
    func `partial download preserves a relation to a task moved into an unavailable project`() async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture)
        var project = fixture.project
        project.localID = UUID()
        project.remoteID = 2
        let destination = project
        try await fixture.store.write { db in try destination.insert(db) }
        fixture.remoteTasks.tasks = [VikunjaTask(
            id: .remote(5), title: "First", projectID: .remote(1),
            subtasks: [TaskRelation(id: .remote(6), title: "Moved", isDone: false, projectID: .remote(2))],
        )]
        fixture.remoteTasks.fetchErrorsByProjectID[2] = VikunjaError.offline
        await #expect(throws: VikunjaError.offline) { try await fixture.engine.pullTasks() }
        let survivor = try await fixture.tasks.fetchTask(id: .remote(5))
        #expect(survivor.subtasks.map(\.id) == [.remote(6)])
        await #expect(throws: VikunjaError.notFound) { try await fixture.tasks.fetchTask(id: .remote(6)) }
        fixture.remoteTasks.fetchErrorsByProjectID = [:]
        fixture.remoteTasks.tasks.append(VikunjaTask(id: .remote(6), title: "Moved", projectID: .remote(2)))
        try await fixture.engine.pullTasks()
        #expect(try await fixture.tasks.fetchTask(id: .remote(6)).projectID == .remote(2))
        #expect(try await fixture.tasks.fetchTask(id: .remote(5)).subtasks.map(\.id) == [.remote(6)])
    }

    @Test
    func `cancellation preserves deletion intent without exposing its relations`() async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture)
        try await fixture.tasks.delete(id: .remote(6))
        fixture.remoteTasks.deleteError = CancellationError()
        await #expect(throws: CancellationError.self) { try await fixture.engine.drainTaskMutations() }
        #expect(try await fixture.tasks.fetchTask(id: .remote(5)).subtasks.isEmpty)
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 2)
        fixture.remoteTasks.deleteError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try TaskRelationRecord.fetchCount($0) } == 0)
    }

    @Test(arguments: [MutationStatus.pending, .failed, .inFlight])
    func `reads hide relations throughout every deletion queue state`(status: MutationStatus) async throws {
        let fixture = try await fixture()
        try await confirmRelation(fixture, kind: .blocking)
        try await fixture.tasks.delete(id: .remote(6))
        try await fixture.store.write { db in
            guard var item = try MutationQueueRecord.filter(Column("operation") == "delete").fetchOne(db) else {
                Issue.record("Missing deletion intent")
                return
            }
            item.status = status
            try item.update(db)
        }
        #expect(try await !fixture.tasks.fetchTask(id: .remote(5)).hasRelations)
        #expect(try await fixture.tasks.fetchTasks(projectID: .remote(1)).first?.hasRelations == false)
        #expect(try await fixture.tasks.searchTasks(query: "First").first?.hasRelations == false)
        await #expect(throws: VikunjaError.notFound) { try await fixture.tasks.fetchTask(id: .remote(6)) }
    }
}
