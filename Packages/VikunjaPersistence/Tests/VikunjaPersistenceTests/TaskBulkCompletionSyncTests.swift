import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private struct NoCompletionSync: SyncRequesting {
    func requestSync() async {}
}

struct TaskBulkCompletionSyncTests {
    private struct Fixture {
        let directory: URL
        let accountID: UUID
        let store: LocalStore
        let local: OfflineTaskRepository
        let remote: FakeTaskRepository
        let engine: SyncEngine
        let tasks: [VikunjaTask]
    }

    private func fixture(synced: Bool = true) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Work", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil,
            position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        try await store.write { db in try project.insert(db) }
        let local = OfflineTaskRepository(localStore: store, accountID: accountID, syncRequester: NoCompletionSync())
        let remote = FakeTaskRepository()
        let engine = makeEngine(store: store, accountID: accountID, remote: remote)
        for title in ["First", "Second"] {
            _ = try await local.create(VikunjaTask(id: .local(UUID()), title: title, projectID: 1))
        }
        if synced {
            try await engine.drainTaskMutations()
        }
        return try await Fixture(
            directory: directory, accountID: accountID, store: store, local: local,
            remote: remote, engine: engine, tasks: local.fetchTasks(projectID: 1),
        )
    }

    private func makeEngine(store: LocalStore, accountID: UUID, remote: FakeTaskRepository) -> SyncEngine {
        SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: remote, relationRepository: FakeTaskRelationRepository(),
            taskBulkUpdateRepository: remote, accountID: accountID,
        )
    }

    private func queue(_ fixture: Fixture) async throws -> [MutationQueueRecord] {
        try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
    }

    @Test func `offline completion persists one visible operation per task and returns immediately`() async throws {
        let fixture = try await fixture()
        let result = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        #expect(result.map(\.isDone) == [true, true])
        #expect(try await fixture.local.fetchTasks(projectID: 1).map(\.isDone) == [true, true])
        #expect(fixture.remote.completionCalls.isEmpty)
        let items = try await queue(fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.operation == .setCompletion && $0.status == .pending })
        let intents = try items.map { try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: $0) }
        #expect(Set(intents.map(\.batchID)).count == 1)
        let operations = try await fixture.store.read { db in
            try PendingSyncOperationsReader.operations(accountID: fixture.accountID, db: db)
        }
        #expect(operations.count == 2)
        #expect(operations.allSatisfy { $0.entity == .task && $0.action == .update && $0.status == .pending })
    }

    @Test func `an invalid selection rolls back all local changes`() async throws {
        let fixture = try await fixture()
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.local.setCompletion(taskIDs: [fixture.tasks[0].id, 99999], isDone: true)
        }
        #expect(try await fixture.local.fetchTasks(projectID: 1).map(\.isDone) == [false, false])
        #expect(try await queue(fixture).isEmpty)
        #expect(try await fixture.local.setCompletion(taskIDs: [], isDone: true).isEmpty)
    }

    @Test func `local and remote aliases select a task once`() async throws {
        let fixture = try await fixture()
        let row = try #require(try await fixture.store.read { db in try TaskRecord.fetchAll(db).first })
        let result = try await fixture.local.setCompletion(
            taskIDs: [.local(row.localID), fixture.tasks[0].id], isDone: true,
        )
        #expect(result.count == 1)
        #expect(try await queue(fixture).count == 1)
    }

    @Test func `one bulk call acknowledges the entire batch`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls.count == 1)
        #expect(Set(fixture.remote.completionCalls[0].ids) == Set(fixture.tasks.map(\.id)))
        #expect(fixture.remote.updatedTasks.isEmpty)
        #expect(fixture.remote.tasks.map(\.isDone) == [true, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `repeated offline completion keeps only the latest intent`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: false)
        #expect(try await queue(fixture).count == 2)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls.count == 1)
        #expect(fixture.remote.completionCalls[0].isDone == false)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `an earlier title edit is sent before completion without losing either change`() async throws {
        let fixture = try await fixture()
        var task = fixture.tasks[0]
        task.title = "Edited offline"
        _ = try await fixture.local.update(task)
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        let local = fixture.local
        fixture.remote.beforeBulkUpdateResponse = {
            let visible = try await local.fetchTasks(projectID: 1)
            #expect(visible.map(\.isDone) == [true, true])
        }
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.updatedTasks.first?.title == "Edited offline")
        #expect(fixture.remote.tasks.first?.title == "Edited offline")
        #expect(fixture.remote.tasks.map(\.isDone) == [true, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a rejected earlier edit defers completion until that edit succeeds`() async throws {
        let fixture = try await fixture()
        var task = fixture.tasks[0]
        task.title = "Pending title"
        _ = try await fixture.local.update(task)
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        fixture.remote.updateError = VikunjaError.server(message: "Unavailable", statusCode: 503)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls.isEmpty)
        #expect(try await queue(fixture).count == 3)
        fixture.remote.updateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls.count == 1)
        #expect(fixture.remote.tasks.first?.title == "Pending title")
        #expect(fixture.remote.tasks.map(\.isDone) == [true, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `an individual completion edit supersedes pending bulk intent for that task`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        var task = try await fixture.local.fetchTask(id: fixture.tasks[0].id)
        task.isDone = false
        _ = try await fixture.local.update(task)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls[0].ids == [fixture.tasks[1].id])
        #expect(fixture.remote.tasks.map(\.isDone) == [false, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a newer batch during upload survives the earlier acknowledgement`() async throws {
        let fixture = try await fixture()
        let local = fixture.local
        let remote = fixture.remote
        let ids = fixture.tasks.map(\.id)
        _ = try await local.setCompletion(taskIDs: ids, isDone: true)
        remote.beforeBulkUpdateResponse = {
            remote.beforeBulkUpdateResponse = nil
            _ = try await local.setCompletion(taskIDs: ids, isDone: false)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(try await local.fetchTasks(projectID: 1).map(\.isDone) == [false, false])
        #expect(try await queue(fixture).count == 2)
        try await fixture.engine.drainTaskMutations()
        #expect(remote.completionCalls.map(\.isDone) == [true, false])
        #expect(remote.tasks.map(\.isDone) == [false, false])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a failed older batch cannot block a newer completion intent`() async throws {
        let fixture = try await fixture()
        let local = fixture.local
        let remote = fixture.remote
        let id = fixture.tasks[0].id
        _ = try await local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        remote.bulkUpdateError = VikunjaError.server(message: "Rejected", statusCode: 403)
        remote.beforeBulkUpdateResponse = {
            remote.beforeBulkUpdateResponse = nil
            _ = try await local.setCompletion(taskIDs: [id], isDone: false)
        }
        try await fixture.engine.drainTaskMutations()
        remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(remote.completionCalls.count == 3)
        #expect(remote.completionCalls[1].ids == [fixture.tasks[1].id])
        #expect(remote.completionCalls[2].ids == [id])
        #expect(remote.tasks.map(\.isDone) == [false, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `an acknowledged individual edit supersedes an older failed completion`() async throws {
        let fixture = try await fixture()
        let local = fixture.local
        let remote = fixture.remote
        let id = fixture.tasks[0].id
        _ = try await local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        remote.bulkUpdateError = VikunjaError.server(message: "Rejected", statusCode: 403)
        remote.beforeBulkUpdateResponse = {
            remote.beforeBulkUpdateResponse = nil
            var task = try await local.fetchTask(id: id)
            task.isDone = false
            _ = try await local.update(task)
        }
        try await fixture.engine.drainTaskMutations()
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).count == 1)
        remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(remote.completionCalls.last?.ids == [fixture.tasks[1].id])
        #expect(remote.tasks.map(\.isDone) == [false, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `title and reminder edits during completion retain their payload and baseline`() async throws {
        let fixture = try await fixture()
        let local = fixture.local
        let remote = fixture.remote
        let id = fixture.tasks[0].id
        _ = try await local.setCompletion(taskIDs: [id], isDone: true)
        remote.beforeBulkUpdateResponse = {
            remote.beforeBulkUpdateResponse = nil
            var task = try await local.fetchTask(id: id)
            task.title = "Changed during upload"
            task.reminders = [TaskReminder(reminder: Date(timeIntervalSince1970: 1_800_000_000))]
            _ = try await local.update(task)
        }
        try await fixture.engine.drainTaskMutations()
        let pending = try await local.fetchTask(id: id)
        #expect(pending.title == "Changed during upload")
        #expect(pending.reminders.count == 1)
        #expect(pending.isDone)
        try await fixture.engine.drainTaskMutations()
        #expect(remote.updatedTasks.last?.title == "Changed during upload")
        #expect(remote.updatedTasks.last?.reminders.count == 1)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `server rejection preserves every task for retry and exposes failure diagnostics`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        fixture.remote.bulkUpdateError = VikunjaError.server(message: "Forbidden", statusCode: 403)
        try await fixture.engine.drainTaskMutations()
        let failed = try await queue(fixture)
        #expect(failed.count == 2)
        #expect(failed.allSatisfy { $0.status == .failed && $0.failureDetails != nil && $0.retryCount == 1 })
        #expect(fixture.remote.updatedTasks.isEmpty)
        #expect(try await fixture.local.fetchTasks(projectID: 1).map(\.isDone) == [true, true])
        fixture.remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls.count == 2)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test(arguments: [false, true])
    func `offline and cancelled uploads release claims without losing pending changes`(cancelled: Bool) async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        fixture.remote.bulkUpdateError = cancelled ? CancellationError() : VikunjaError.offline
        do {
            try await fixture.engine.drainTaskMutations()
            Issue.record("Expected interrupted upload")
        } catch {
            #expect(cancelled ? error is CancellationError : (error as? VikunjaError) == .offline)
        }
        let items = try await queue(fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.status == .pending && $0.retryCount == 0 })
        fixture.remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `one server conflict blocks the whole batch and remains recoverable`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        fixture.remote.tasks[0].updated = fixture.remote.tasks[0].updated?.addingTimeInterval(10)
        fixture.remote.tasks[0].title = "Edited by another client"
        try await fixture.engine.pullTasks()
        try await fixture.engine.drainTaskMutations()
        let items = try await queue(fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.needsConflictResolution && $0.canDiscardConflict })
        #expect(fixture.remote.completionCalls.isEmpty)
    }

    @Test func `tasks created offline resolve their IDs before bulk upload`() async throws {
        let fixture = try await fixture(synced: false)
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.createdTasks.count == 2)
        #expect(fixture.remote.completionCalls.count == 1)
        #expect(fixture.remote.completionCalls[0].ids.allSatisfy { $0.remoteValue != nil })
        #expect(fixture.remote.tasks.map(\.isDone) == [true, true])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `deleting during completion remains deleted after the response and the next pull`() async throws {
        let fixture = try await fixture()
        let local = fixture.local
        let id = fixture.tasks[0].id
        _ = try await local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        fixture.remote.beforeBulkUpdateResponse = { try await local.delete(id: id) }
        try await fixture.engine.drainTaskMutations()
        #expect(try await local.fetchTasks(projectID: 1).count == 1)
        try await fixture.engine.pullTasks()
        #expect(try await local.fetchTasks(projectID: 1).count == 1)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.deletedIDs.count == 1)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `overlapping drains never send a claimed batch twice`() async throws {
        let fixture = try await fixture()
        let engine = fixture.engine
        let remote = fixture.remote
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        remote.beforeBulkUpdateResponse = {
            remote.beforeBulkUpdateResponse = nil
            try await engine.drainTaskMutations()
        }
        try await engine.drainTaskMutations()
        #expect(remote.completionCalls.count == 1)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `bulk acknowledgement is one database transaction`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        let items = try await queue(fixture)
        let lastID = try #require(items.last?.id)
        try await fixture.store.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_completion_ack BEFORE DELETE ON mutationQueueItem
            WHEN OLD.id = \(lastID) BEGIN SELECT RAISE(ABORT, 'test failure'); END;
            """)
        }
        try await fixture.engine.drainTaskMutations()
        let pending = try await queue(fixture)
        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.status == .failed })
        try await fixture.store.write { db in try db.execute(sql: "DROP TRIGGER reject_completion_ack") }
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `selection cannot modify a task belonging to another account`() async throws {
        let fixture = try await fixture()
        let otherAccount = UUID()
        let otherProject = ProjectRecord(
            localID: UUID(), accountID: otherAccount, remoteID: 1, title: "Other", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil,
            position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        try await fixture.store.write { db in try otherProject.insert(db) }
        let other = OfflineTaskRepository(
            localStore: fixture.store, accountID: otherAccount, syncRequester: NoCompletionSync(),
        )
        let task = try await other.create(VikunjaTask(id: .local(UUID()), title: "Private", projectID: 1))
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.local.setCompletion(taskIDs: [fixture.tasks[0].id, task.id], isDone: true)
        }
        #expect(try await fixture.local.fetchTask(id: fixture.tasks[0].id).isDone == false)
        #expect(try await other.fetchTask(id: task.id).isDone == false)
    }

    @Test func `a claimed batch survives reopening the database`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setCompletion(taskIDs: fixture.tasks.map(\.id), isDone: true)
        try await fixture.store.write { db in
            for var item in try MutationQueueRecord.fetchAll(db) {
                item.status = .inFlight
                try item.update(db)
            }
        }
        let reopened = try LocalStore(directory: fixture.directory)
        let engine = makeEngine(store: reopened, accountID: fixture.accountID, remote: fixture.remote)
        try await engine.drainTaskMutations()
        #expect(fixture.remote.completionCalls.count == 1)
        #expect(try await queue(fixture).isEmpty)
    }
}
