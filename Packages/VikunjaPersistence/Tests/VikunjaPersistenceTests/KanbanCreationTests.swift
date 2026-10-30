import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor CreationScheduler: SyncRequesting {
    private(set) var calls = 0
    func requestSync() async {
        calls += 1
    }
}

private actor CreationRemote: BucketRepositoryProtocol {
    private(set) var requests: [(VikunjaTask, Int)] = []
    var responseHook: (@Sendable () async throws -> Void)?
    var failure: VikunjaError?
    func configure(failure: VikunjaError? = nil, hook: (@Sendable () async throws -> Void)? = nil) {
        self.failure = failure
        responseHook = hook
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        requests.append((task, bucketID))
        try await responseHook?()
        if let failure {
            throw failure
        }
        var result = task
        result = VikunjaTask(
            id: .remote(500),
            title: task.title,
            description: task.description,
            isDone: task.isDone,
            dueDate: task.dueDate,
            priority: task.priority,
            projectID: task.projectID,
            reminders: task.reminders,
            updated: Date(),
        )
        return result
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        throw VikunjaError.notFound
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        []
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int, viewID: Int?) async throws -> VikunjaTask {
        throw VikunjaError.notFound
    }
}

struct KanbanCreationTests {
    private struct Fixture {
        let store: LocalStore
        let directory: URL
        let accountID: UUID
        let board: OfflineKanbanBoardRepository
        let tasks: OfflineTaskRepository
        let engine: SyncEngine
        let remote: CreationRemote
        let scheduler: CreationScheduler
    }

    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        try await store.write { db in try Self.seedBoard(accountID: accountID, db: db) }
        let remote = CreationRemote()
        let scheduler = CreationScheduler()
        let tasks = OfflineTaskRepository(localStore: store, accountID: accountID, syncRequester: scheduler)
        let engine = SyncEngine(
            localStore: store,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(),
            accountID: accountID,
            bucketRepository: remote,
            capabilityProvider: KanbanCapabilities(),
        )
        return Fixture(
            store: store,
            directory: directory,
            accountID: accountID,
            board: OfflineKanbanBoardRepository(localStore: store, accountID: accountID, syncRequester: scheduler),
            tasks: tasks,
            engine: engine,
            remote: remote,
            scheduler: scheduler,
        )
    }

    private static func seedBoard(accountID: UUID, db: Database) throws {
        let projectID = UUID()
        let viewID = UUID()
        try ProjectRecord(
            localID: projectID,
            accountID: accountID,
            remoteID: 1,
            title: "Work",
            description: nil,
            isArchived: false,
            isFavorite: false,
            parentProjectLocalID: nil,
            position: 0,
            hexColor: "",
            serverUpdatedAt: nil,
        ).insert(db)
        try KanbanViewRecord(
            localID: viewID,
            accountID: accountID,
            projectLocalID: projectID,
            remoteID: 10,
            mode: "manual",
            filterQuery: "",
            defaultBucketID: 20,
            doneBucketID: 21,
            lastCompletePullAt: Date(),
        ).insert(db)
        for id in [20, 21] {
            try KanbanBucketRecord(
                localID: UUID(),
                accountID: accountID,
                projectLocalID: projectID,
                viewLocalID: viewID,
                remoteID: id,
                title: "Column",
                position: Double(id),
                limit: 0,
                serverCount: 0,
            ).insert(db)
        }
    }

    @Test func `offline creation is shared durable and schedules without upload`() async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(
            title: "Offline", projectID: .remote(1), viewID: 10, bucketID: 21,
        )
        #expect(task.id.remoteValue == nil)
        #expect(task.isDone)
        #expect(try await fixture.tasks.fetchTasks(projectID: .remote(1)).map(\.id) == [task.id])
        #expect(await fixture.remote.requests.isEmpty)
        #expect(await fixture.scheduler.calls == 1)
        let reopened = try LocalStore(directory: fixture.directory)
        let board = OfflineKanbanBoardRepository(
            localStore: reopened,
            accountID: fixture.accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        guard case let .available(snapshot) = try await board.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Missing board"); return
        }
        #expect(snapshot.buckets[1].tasks.map(\.id) == [task.id])
        #expect(try await reopened.read { try MutationQueueRecord.fetchCount($0) } == 1)
    }

    @Test func `creation failure rolls back task assignment and queue`() async throws {
        let fixture = try await fixture()
        try await fixture.store.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_test_create BEFORE INSERT ON mutationQueueItem
            BEGIN SELECT RAISE(ABORT, 'Simulated queue failure'); END;
            """)
        }
        await #expect(throws: DatabaseError.self) {
            try await fixture.board.createTask(
                title: "Rollback", projectID: .remote(1), viewID: 10, bucketID: 20,
            )
        }
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try KanbanAssignmentRecord.fetchCount($0) } == 0)
        #expect(await fixture.scheduler.calls == 0)
    }

    @Test func `edits retain destination and successful upload retains identity`() async throws {
        let fixture = try await fixture()
        var task = try await fixture.board.createTask(
            title: "Original", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        task.title = "Edited"
        task.description = "Description"
        task.priority = .high
        _ = try await fixture.tasks.update(task)
        try await fixture.engine.drainTaskMutations()
        let requests = await fixture.remote.requests
        #expect(requests.count == 1)
        #expect(requests[0].0.title == "Edited")
        #expect(requests[0].0.description == "Description")
        #expect(requests[0].0.priority == .high)
        #expect(requests[0].1 == 20)
        #expect(try await fixture.tasks.fetchTask(id: task.id).id == .remote(500))
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 1)
        #expect(try await fixture.store.read { try KanbanAssignmentRecord.fetchCount($0) } == 1)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test func `edits during upload become update and do not repeat post`() async throws {
        let fixture = try await fixture()
        let original = try await fixture.board.createTask(
            title: "Original", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        await fixture.remote.configure(hook: {
            var changed = original
            changed.title = "During upload"
            _ = try await fixture.tasks.update(changed)
        })
        try await fixture.engine.drainTaskMutations()
        let queued = try await fixture.store.read { try MutationQueueRecord.fetchAll($0) }
        #expect(queued.map(\.operation) == [.update])
        #expect(try await fixture.tasks.fetchTask(id: original.id).title == "During upload")
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.count == 1)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test func `deletes before and during upload cancel or compensate`() async throws {
        let fixture = try await fixture()
        let cancelled = try await fixture.board.createTask(
            title: "Cancel", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        try await fixture.tasks.delete(id: cancelled.id)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.isEmpty)
        let original = try await fixture.board.createTask(
            title: "Delete", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        await fixture.remote.configure(hook: { try await fixture.tasks.delete(id: original.id) })
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchAll($0).map(\.operation) } == [.delete])
        #expect(try await fixture.tasks.fetchTasks(projectID: .remote(1)).isEmpty)
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test(arguments: [VikunjaError.timeout, .server(message: "Full", statusCode: 412)])
    func `rejected or unconfirmed creation remains actionable without automatic retry`(error: VikunjaError) async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(
            title: "Review", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        await fixture.remote.configure(failure: error)
        try await fixture.engine.drainTaskMutations()
        var edit = task
        edit.title = "Still blocked"
        _ = try await fixture.tasks.update(edit)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.count == 1)
        let pending = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(pending.count == 1)
        #expect(pending[0].status == .failed)
        #expect(pending[0].failureMessage != nil)
        try await fixture.store.discardConflictedPendingSyncOperation(id: pending[0].id, accountID: fixture.accountID)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 1)
        #expect(try await fixture.tasks.fetchTasks(projectID: .remote(1)).count == 1)
    }

    @Test func `interrupted creation is not posted again after restart`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.board.createTask(
            title: "Interrupted", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        try await fixture.store.write { db in
            var queued = try #require(MutationQueueRecord.fetchAll(db).first)
            queued.status = .inFlight
            try queued.update(db)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.isEmpty)
        let pending = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(pending[0].status == .failed)
        #expect(pending[0].failureMessage?.contains("Automatic retry is paused") == true)
    }

    @Test func `destination deleted before upload is reported without sending`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.board.createTask(title: "Missing", projectID: .remote(1), viewID: 10, bucketID: 20)
        try await fixture.store.write { db in
            let bucket = try #require(KanbanBucketRecord.fetchAll(db).first { $0.remoteID == 20 })
            try bucket.delete(db)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.isEmpty)
        let pending = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(pending[0].failureMessage?.contains("column unavailable") == true)
    }

    @Test(arguments: ["filter", "missing", "unsynced"])
    func `unsupported or uninitialized board cannot accept creation`(state: String) async throws {
        let fixture = try await fixture()
        try await fixture.store.write { db in
            var view = try #require(KanbanViewRecord.fetchAll(db).first)
            if state == "filter" {
                view.mode = "filter"
            }
            if state == "missing" {
                view.lastCompletePullAt = nil
            }
            try view.update(db)
            if state == "unsynced" {
                var project = try #require(ProjectRecord.fetchAll(db).first)
                project.remoteID = nil
                try project.update(db)
            }
        }
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.board.createTask(title: "Blocked", projectID: .remote(1), viewID: 10, bucketID: 20)
        }
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test func `legacy payload decodes and invalid destination does not write`() async throws {
        let fixture = try await fixture()
        let legacy = TaskCreateOrUpdatePayload(
            title: "Old",
            description: nil,
            isDone: false,
            dueDate: nil,
            priority: 0,
            projectLocalID: UUID(),
            baseUpdatedAt: nil,
            reminders: nil,
        )
        let data = try JSONEncoder().encode(legacy)
        #expect(try JSONDecoder().decode(TaskCreateOrUpdatePayload.self, from: data).kanbanDestination == nil)
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.board.createTask(title: "Invalid", projectID: .remote(1), viewID: 99, bucketID: 20)
        }
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 0)
    }
}
