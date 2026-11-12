import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct TaskBulkPartialProgressTests {
    private static let changes: [TaskBulkChange] = [
        .completion(isDone: true), .dueDate(Date(timeIntervalSince1970: 1_900_000_000)),
    ]

    fileprivate struct Fixture {
        let directory: URL
        let accountID: UUID
        let store: LocalStore
        let local: OfflineTaskRepository
        let remote: FakeTaskRepository
        let engine: SyncEngine
        let tasks: [VikunjaTask]
        var ids: [EntityID] {
            tasks.map(\.id)
        }
    }

    fileprivate func makeEngine(_ store: LocalStore, accountID: UUID, remote: FakeTaskRepository) -> SyncEngine {
        SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: remote, relationRepository: FakeTaskRelationRepository(),
            taskBulkUpdateRepository: remote, accountID: accountID,
        )
    }

    fileprivate func fixture(lifecycle: DatabaseExecutionLifecycle? = nil) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accountID = UUID()
        let store = try LocalStore(directory: directory, executionLifecycle: lifecycle)
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Work", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil,
            position: 0, hexColor: "", serverUpdatedAt: nil,
        )
        try await store.write { db in try project.insert(db) }
        let local = OfflineTaskRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        let remote = FakeTaskRepository()
        let engine = makeEngine(store, accountID: accountID, remote: remote)
        for title in ["First", "Second", "Third"] {
            _ = try await local.create(VikunjaTask(id: .local(UUID()), title: title, projectID: 1))
        }
        try await engine.drainTaskMutations()
        return try await Fixture(
            directory: directory, accountID: accountID, store: store, local: local,
            remote: remote, engine: engine, tasks: local.fetchTasks(projectID: 1),
        )
    }

    fileprivate func queue(_ fixture: Fixture) async throws -> [MutationQueueRecord] {
        try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
    }

    private func matches(_ task: VikunjaTask, _ change: TaskBulkChange) -> Bool {
        switch change {
        case let .completion(done): task.isDone == done
        case let .dueDate(date): task.dueDate == date
        }
    }

    @Test(arguments: Self.changes)
    func `all conflicting members stay recoverable without submitting an empty request`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        for index in fixture.remote.tasks.indices {
            fixture.remote.tasks[index].title = "External edit"
        }
        try await fixture.engine.drainTaskMutations()
        try await fixture.engine.drainTaskMutations()
        let remaining = try await queue(fixture)
        #expect(remaining.count == fixture.ids.count)
        #expect(remaining.allSatisfy { $0.needsConflictResolution && $0.canDiscardConflict && $0.retryCount == 0 })
        #expect(fixture.remote.bulkUpdateCalls.isEmpty)
    }

    @Test(arguments: Self.changes)
    func `overlapping drains during verification never submit the same intent twice`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let remote = fixture.remote
        let engine = fixture.engine
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        remote.fetchTaskResponse = { id in
            remote.fetchTaskResponse = nil
            try await engine.drainTaskMutations()
            return try #require(remote.tasks.first { $0.id == id })
        }
        try await engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [fixture.ids])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test(arguments: Self.changes)
    func `only conflicting members remain while healthy members share one bulk submission`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        let original = try await queue(fixture)
        let batchID = try TaskBulkIntent(item: #require(original.first)).batchID
        fixture.remote.tasks[0].title = "External edit"
        try await fixture.engine.drainTaskMutations()
        let remaining = try await queue(fixture)
        #expect(remaining.count == 1)
        #expect(remaining[0].targetLocalID == original[0].targetLocalID)
        #expect(remaining[0].needsConflictResolution && remaining[0].canDiscardConflict)
        #expect(try TaskBulkIntent(item: remaining[0]).batchID == batchID)
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [Array(fixture.ids.dropFirst())])
        #expect(fixture.remote.tasks.dropFirst().allSatisfy { matches($0, change) })
        #expect(!matches(fixture.remote.tasks[0], change))
        #expect(fixture.remote.tasks[0].title == "External edit")
        #expect(fixture.remote.updatedTasks.isEmpty)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).count == 1)
    }

    @Test(arguments: Self.changes)
    func `legacy date conflicts are isolated without inventing field baselines`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        try await fixture.store.write { db in
            for var item in try MutationQueueRecord.fetchAll(db) {
                var intent = try TaskBulkIntent(item: item)
                intent.baseFields = nil
                item.payload = try intent.encodedPayload()
                try item.update(db)
            }
        }
        fixture.remote.tasks[0].title = "External edit"
        fixture.remote.tasks[0].updated = fixture.remote.tasks[0].updated?.addingTimeInterval(10)
        try await fixture.engine.pullTasks()
        try await fixture.engine.drainTaskMutations()
        let remaining = try await queue(fixture)
        #expect(remaining.count == 1 && remaining[0].needsConflictResolution)
        #expect(try TaskBulkIntent(item: remaining[0]).baseFields == nil)
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [Array(fixture.ids.dropFirst())])
    }

    @Test(arguments: Self.changes)
    func `a failed verification retries independently while an existing sibling conflict remains`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let remote = fixture.remote
        let failedID = fixture.ids[1]
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        remote.tasks[0].title = "External edit"
        remote.fetchTaskResponse = { id in
            if id == failedID {
                throw VikunjaError.notFound
            }
            return try #require(remote.tasks.first { $0.id == id })
        }
        try await fixture.engine.drainTaskMutations()
        let remaining = try await queue(fixture)
        #expect(remaining.count == 2)
        #expect(remaining.filter(\.needsConflictResolution).count == 1)
        let failed = remaining.filter { $0.status == .failed && !$0.needsConflictResolution && $0.retryCount == 1 }
        #expect(failed.count == 1)
        #expect(remote.bulkUpdateCalls.map(\.ids) == [[fixture.ids[2]]])
        remote.fetchTaskResponse = nil
        try await fixture.engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [[fixture.ids[2]], [failedID]])
        let final = try await queue(fixture)
        #expect(final.count == 1 && final[0].needsConflictResolution)
    }

    @Test(arguments: Self.changes)
    func `a rejected subset preserves only its members for retry alongside the separate conflict`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        fixture.remote.tasks[0].title = "External edit"
        fixture.remote.bulkUpdateError = VikunjaError.server(message: "Rejected", statusCode: 403)
        try await fixture.engine.drainTaskMutations()
        let remaining = try await queue(fixture)
        #expect(remaining.count == 3)
        #expect(remaining.filter { $0.needsConflictResolution && $0.retryCount == 0 }.count == 1)
        let failed = remaining.filter { $0.status == .failed && !$0.needsConflictResolution && $0.retryCount == 1 }
        #expect(failed.count == 2)
        fixture.remote.bulkUpdateError = nil
        try await fixture.engine.drainTaskMutations()
        let submitted = Array(fixture.ids.dropFirst())
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [submitted, submitted])
        let final = try await queue(fixture)
        #expect(final.count == 1 && final[0].needsConflictResolution)
    }

    @Test(arguments: Self.changes)
    func `an unsynced task waits for creation without blocking synchronized siblings`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let created = try await fixture.local.create(VikunjaTask(id: .local(UUID()), title: "New", projectID: 1))
        _ = try await fixture.local.apply(change, toTaskIDs: [created.id] + fixture.ids)
        fixture.remote.createError = VikunjaError.server(message: "Temporary rejection", statusCode: 503)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [fixture.ids])
        let waiting = try await queue(fixture)
        #expect(waiting.count == 2 && waiting.allSatisfy { !$0.needsConflictResolution })
        #expect(waiting.first { $0.operation.isBulkTaskChange }?.status == .pending)
        fixture.remote.createError = nil
        try await fixture.engine.drainTaskMutations()
        let synced = try await fixture.local.fetchTask(id: created.id)
        #expect(matches(synced, change))
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [fixture.ids, [synced.id]])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test
    func `an earlier conflict blocks only later intent for the same task`() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.local.setCompletion(taskIDs: fixture.ids, isDone: true)
        fixture.remote.tasks[0].title = "External edit"
        try await fixture.engine.drainTaskMutations()
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        _ = try await fixture.local.setDueDate(taskIDs: fixture.ids, dueDate: date)
        try await fixture.engine.drainTaskMutations()
        let submitted = Array(fixture.ids.dropFirst())
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [submitted, submitted])
        let remaining = try await queue(fixture)
        #expect(remaining.count == 2)
        #expect(remaining.filter(\.needsConflictResolution).count == 1)
        #expect(remaining.first { $0.operation == .setDueDate }?.status == .pending)
        #expect(fixture.remote.tasks[0].dueDate == nil)
        #expect(fixture.remote.tasks.dropFirst().allSatisfy { $0.dueDate == date })
    }

    @Test(arguments: Self.changes)
    func `reopening preserves the conflict and sends only a deferred surviving member`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let remote = fixture.remote
        let waitingID = fixture.ids[1]
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        remote.tasks[0].title = "External edit"
        remote.fetchTaskResponse = { id in
            if id == waitingID {
                throw VikunjaError.server(message: "Denied", statusCode: 403)
            }
            return try #require(remote.tasks.first { $0.id == id })
        }
        try await fixture.engine.drainTaskMutations()
        let reopened = try LocalStore(directory: fixture.directory)
        let engine = makeEngine(reopened, accountID: fixture.accountID, remote: remote)
        remote.fetchTaskResponse = nil
        try await engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [[fixture.ids[2]], [waitingID]])
        let remaining = try await reopened.pendingSyncOperations(accountID: fixture.accountID)
        #expect(remaining.count == 1 && remaining[0].needsConflictResolution)
    }

    @Test(arguments: Self.changes, [false, true])
    func `offline or cancelled verification sends nothing and keeps unclaimed intent`(
        _ change: TaskBulkChange, cancelled: Bool,
    ) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let remote = fixture.remote
        let interruptedID = fixture.ids[1]
        _ = try await fixture.local.apply(change, toTaskIDs: fixture.ids)
        remote.fetchTaskResponse = { id in
            if id == interruptedID {
                if cancelled {
                    throw URLError(.cancelled)
                }
                throw VikunjaError.offline
            }
            return try #require(remote.tasks.first { $0.id == id })
        }
        do {
            try await fixture.engine.drainTaskMutations()
            Issue.record("Expected interrupted verification")
        } catch {
            #expect(cancelled ? error is CancellationError : (error as? VikunjaError) == .offline)
        }
        let remaining = try await queue(fixture)
        #expect(remaining.count == 3)
        #expect(remaining.allSatisfy { $0.status == .pending && $0.retryCount == 0 && !$0.needsConflictResolution })
        #expect(remote.bulkUpdateCalls.isEmpty)
        remote.fetchTaskResponse = nil
        try await fixture.engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [fixture.ids])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test(arguments: Self.changes)
    func `replacing one member during verification never claims its obsolete payload`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let remote = fixture.remote
        let local = fixture.local
        let replacedID = fixture.ids[0]
        _ = try await local.apply(change, toTaskIDs: fixture.ids)
        remote.fetchTaskResponse = { id in
            if id == replacedID {
                remote.fetchTaskResponse = nil
                _ = try await local.apply(change, toTaskIDs: [id])
            }
            return try #require(remote.tasks.first { $0.id == id })
        }
        try await fixture.engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [Array(fixture.ids.dropFirst())])
        let remaining = try await queue(fixture)
        #expect(remaining.count == 1 && remaining[0].status == .pending && !remaining[0].needsConflictResolution)
        try await fixture.engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [Array(fixture.ids.dropFirst()), [replacedID]])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test(arguments: Self.changes)
    func `deleting during verification removes that member before claiming the remaining subset`(_ change: TaskBulkChange) async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let remote = fixture.remote
        let local = fixture.local
        let deletedID = fixture.ids[0]
        _ = try await local.apply(change, toTaskIDs: fixture.ids)
        remote.fetchTaskResponse = { id in
            if id == deletedID {
                remote.fetchTaskResponse = nil
                try await local.delete(id: id)
            }
            return try #require(remote.tasks.first { $0.id == id })
        }
        try await fixture.engine.drainTaskMutations()
        #expect(remote.bulkUpdateCalls.map(\.ids) == [Array(fixture.ids.dropFirst())])
        #expect(try await local.fetchTasks(projectID: 1).count == 2)
        try await fixture.engine.drainTaskMutations()
        #expect(try remote.deletedIDs == [#require(deletedID.remoteValue)])
        #expect(try await queue(fixture).isEmpty)
    }
}

/// Managed database stores share process-wide GRDB suspension notifications.
/// Keep this case in the serialized lifecycle suite, alongside its other stores.
extension DatabaseExecutionLifecycleTests {
    @Test
    func `suspension after submitting a subset recovers only its claims and preserves its sibling conflict`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let helper = TaskBulkPartialProgressTests()
        let fixture = try await helper.fixture(lifecycle: lifecycle)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.local.setCompletion(taskIDs: fixture.ids, isDone: true)
        fixture.remote.tasks[0].title = "External edit"
        fixture.remote.beforeBulkUpdateResponse = {
            lifecycle.setForeground(false)
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) { try await fixture.engine.drainTaskMutations() }
        let interrupted = try await helper.queue(fixture)
        #expect(interrupted.filter(\.needsConflictResolution).count == 1)
        #expect(interrupted.filter { $0.status == .inFlight && !$0.needsConflictResolution }.count == 2)
        #expect(interrupted.allSatisfy { $0.retryCount == 0 && $0.lastError == nil })
        lifecycle.setForeground(true)
        fixture.remote.beforeBulkUpdateResponse = nil
        let reopened = try LocalStore(directory: fixture.directory, executionLifecycle: lifecycle)
        let engine = helper.makeEngine(reopened, accountID: fixture.accountID, remote: fixture.remote)
        try await engine.drainTaskMutations()
        let submitted = Array(fixture.ids.dropFirst())
        #expect(fixture.remote.bulkUpdateCalls.map(\.ids) == [submitted, submitted])
        let remaining = try await helper.queue(fixture)
        #expect(remaining.count == 1 && remaining[0].needsConflictResolution)
    }
}
