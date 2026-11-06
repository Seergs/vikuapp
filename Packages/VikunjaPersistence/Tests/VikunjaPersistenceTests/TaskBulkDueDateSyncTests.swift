import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private struct NoDueDateSync: SyncRequesting {
    func requestSync() async {}
}

/// The bulk due-date path shares its drain with bulk completion (covered in
/// `TaskBulkCompletionSyncTests`). These tests cover what is specific to due
/// dates and how both kinds of bulk intent interact on the same task.
struct TaskBulkDueDateSyncTests {
    private static let overdue = Date(timeIntervalSince1970: 1_790_000_000)
    private static let rescheduled = Date(timeIntervalSince1970: 1_800_000_000)
    private static let later = Date(timeIntervalSince1970: 1_800_086_400)

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
        let local = OfflineTaskRepository(localStore: store, accountID: accountID, syncRequester: NoDueDateSync())
        let remote = FakeTaskRepository()
        let engine = makeEngine(store: store, accountID: accountID, remote: remote)
        for title in ["First", "Second"] {
            _ = try await local.create(VikunjaTask(
                id: .local(UUID()), title: title, dueDate: Self.overdue, projectID: 1,
            ))
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

    @Test func `offline reschedule persists one visible operation per task and changes only the due date`() async throws {
        let fixture = try await fixture()
        let result = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        #expect(result.map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        let visible = try await fixture.local.fetchTasks(projectID: 1)
        #expect(visible.map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        #expect(visible.map(\.title) == ["First", "Second"])
        #expect(visible.map(\.isDone) == [false, false])
        #expect(fixture.remote.bulkUpdateCalls.isEmpty)
        let items = try await queue(fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.operation == .setDueDate && $0.status == .pending })
        let intents = try items.map { try KanbanLocalMutations.decode(TaskDueDatePayload.self, item: $0) }
        #expect(Set(intents.map(\.batchID)).count == 1)
        #expect(intents.allSatisfy { $0.dueDate == Self.rescheduled })
        let operations = try await fixture.store.read { db in
            try PendingSyncOperationsReader.operations(accountID: fixture.accountID, db: db)
        }
        #expect(operations.count == 2)
        #expect(operations.allSatisfy { $0.entity == .task && $0.action == .update && $0.status == .pending })
    }

    @Test func `an invalid selection rolls back every local due date`() async throws {
        let fixture = try await fixture()
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.local.setDueDate(taskIDs: [fixture.tasks[0].id, 99999], dueDate: Self.rescheduled)
        }
        #expect(try await fixture.local.fetchTasks(projectID: 1).map(\.dueDate) == [Self.overdue, Self.overdue])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `one bulk call reschedules and acknowledges the entire batch`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.dueDateCalls.count == 1)
        #expect(Set(fixture.remote.dueDateCalls[0].ids) == Set(fixture.tasks.map(\.id)))
        #expect(fixture.remote.dueDateCalls[0].dueDate == Self.rescheduled)
        #expect(fixture.remote.completionCalls.isEmpty)
        #expect(fixture.remote.updatedTasks.isEmpty)
        #expect(fixture.remote.tasks.map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        #expect(try await fixture.local.fetchTasks(projectID: 1).map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `repeated offline reschedule keeps only the latest date`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.later)
        #expect(try await queue(fixture).count == 2)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.dueDateCalls.map(\.dueDate) == [Self.later])
        #expect(fixture.remote.tasks.map(\.dueDate) == [Self.later, Self.later])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `completion and reschedule of the same tasks are both sent in order`() async throws {
        let fixture = try await fixture()
        let ids = fixture.tasks.map(\.id)
        _ = try await fixture.local.setCompletion(taskIDs: ids, isDone: true)
        _ = try await fixture.local.setDueDate(taskIDs: ids, dueDate: Self.rescheduled)
        // A due-date intent must not replace a completion intent for that task.
        #expect(try await queue(fixture).count == 4)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.bulkUpdateCalls.map(\.change) == [.completion(isDone: true), .dueDate(Self.rescheduled)])
        #expect(fixture.remote.tasks.map(\.isDone) == [true, true])
        #expect(fixture.remote.tasks.map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a rejected earlier completion defers a later reschedule of that task`() async throws {
        let fixture = try await fixture()
        let ids = fixture.tasks.map(\.id)
        _ = try await fixture.local.setCompletion(taskIDs: ids, isDone: true)
        _ = try await fixture.local.setDueDate(taskIDs: ids, dueDate: Self.rescheduled)
        fixture.remote.bulkUpdateError = VikunjaError.server(message: "Unavailable", statusCode: 503)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.bulkUpdateCalls.map(\.change) == [.completion(isDone: true)])
        #expect(try await queue(fixture).count == 4)
        fixture.remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.bulkUpdateCalls.map(\.change).suffix(2) == [
            .completion(isDone: true), .dueDate(Self.rescheduled),
        ])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `an individual due date edit supersedes pending bulk reschedule but not completion`() async throws {
        let fixture = try await fixture()
        let ids = fixture.tasks.map(\.id)
        _ = try await fixture.local.setCompletion(taskIDs: [ids[0]], isDone: true)
        _ = try await fixture.local.setDueDate(taskIDs: ids, dueDate: Self.rescheduled)
        var task = try await fixture.local.fetchTask(id: ids[0])
        task.dueDate = Self.later
        _ = try await fixture.local.update(task)
        let operations = try await queue(fixture).filter(\.operation.isBulkTaskChange).map(\.operation)
        #expect(operations.sorted { $0.rawValue < $1.rawValue } == [.setCompletion, .setDueDate])
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.dueDateCalls.map(\.ids) == [[ids[1]]])
        #expect(fixture.remote.tasks.map(\.dueDate) == [Self.later, Self.rescheduled])
        #expect(fixture.remote.tasks.map(\.isDone) == [true, false])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a title edit during upload keeps the rescheduled date and its own payload`() async throws {
        let fixture = try await fixture()
        let local = fixture.local
        let remote = fixture.remote
        let id = fixture.tasks[0].id
        _ = try await local.setDueDate(taskIDs: [id], dueDate: Self.rescheduled)
        remote.beforeBulkUpdateResponse = {
            remote.beforeBulkUpdateResponse = nil
            var task = try await local.fetchTask(id: id)
            task.title = "Changed during upload"
            _ = try await local.update(task)
        }
        try await fixture.engine.drainTaskMutations()
        let pending = try await local.fetchTask(id: id)
        #expect(pending.title == "Changed during upload")
        #expect(pending.dueDate == Self.rescheduled)
        try await fixture.engine.drainTaskMutations()
        #expect(remote.updatedTasks.last?.title == "Changed during upload")
        #expect(remote.updatedTasks.last?.dueDate == Self.rescheduled)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `server rejection keeps the local date and every task for retry`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        fixture.remote.bulkUpdateError = VikunjaError.server(message: "Forbidden", statusCode: 403)
        try await fixture.engine.drainTaskMutations()
        let failed = try await queue(fixture)
        #expect(failed.count == 2)
        #expect(failed.allSatisfy { $0.status == .failed && $0.failureDetails != nil && $0.retryCount == 1 })
        #expect(try await fixture.local.fetchTasks(projectID: 1).map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        fixture.remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.tasks.map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `going offline during upload releases the claim without counting a failure`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        fixture.remote.bulkUpdateError = VikunjaError.offline
        await #expect(throws: VikunjaError.offline) {
            try await fixture.engine.drainTaskMutations()
        }
        let items = try await queue(fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.status == .pending && $0.retryCount == 0 })
        fixture.remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a newer server edit blocks the whole reschedule as a recoverable conflict`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        fixture.remote.tasks[0].updated = fixture.remote.tasks[0].updated?.addingTimeInterval(10)
        try await fixture.engine.pullTasks()
        try await fixture.engine.drainTaskMutations()
        let items = try await queue(fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.needsConflictResolution && $0.canDiscardConflict })
        #expect(fixture.remote.dueDateCalls.isEmpty)
        // Like every other conflict, the newer server state is shown while
        // the queued intent waits for the user's resolution in Pending Sync.
        let conflicted = try await fixture.local.fetchTask(id: fixture.tasks[0].id)
        #expect(conflicted.dueDate == Self.overdue)
    }

    @Test func `tasks created offline resolve their IDs before the reschedule is sent`() async throws {
        let fixture = try await fixture(synced: false)
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.createdTasks.count == 2)
        #expect(fixture.remote.dueDateCalls.count == 1)
        #expect(fixture.remote.dueDateCalls[0].ids.allSatisfy { $0.remoteValue != nil })
        #expect(fixture.remote.tasks.map(\.dueDate) == [Self.rescheduled, Self.rescheduled])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `a claimed reschedule survives reopening the database`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.local.setDueDate(taskIDs: fixture.tasks.map(\.id), dueDate: Self.rescheduled)
        try await fixture.store.write { db in
            for var item in try MutationQueueRecord.fetchAll(db) {
                item.status = .inFlight
                try item.update(db)
            }
        }
        let reopened = try LocalStore(directory: fixture.directory)
        let engine = makeEngine(store: reopened, accountID: fixture.accountID, remote: fixture.remote)
        try await engine.drainTaskMutations()
        #expect(fixture.remote.dueDateCalls.count == 1)
        #expect(try await queue(fixture).isEmpty)
    }
}
