import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor CreationReachability: ReachabilityMonitoring {
    let isReachable: Bool
    init(online: Bool) {
        self.isReachable = online
    }

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

private actor CreationNotifications {
    private(set) var accounts: [UUID] = []
    func record(_ account: UUID) {
        accounts.append(account)
    }
}

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
    private(set) var downloadRequests = 0
    var download: KanbanDownload?
    func setDownload(_ download: KanbanDownload) {
        self.download = download
    }

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
        downloadRequests += 1
        if let download {
            return download
        }
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
        let notifications: CreationNotifications
    }

    private func fixture(online: Bool = false) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        try await store.write { db in try Self.seedBoard(accountID: accountID, db: db) }
        let remote = CreationRemote()
        let notifications = CreationNotifications()
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
            onKanbanCreationRejected: { await notifications.record($0) },
        )
        return Fixture(
            store: store,
            directory: directory,
            accountID: accountID,
            board: OfflineKanbanBoardRepository(
                localStore: store, accountID: accountID, syncRequester: scheduler,
                reachability: CreationReachability(online: online),
            ),
            tasks: tasks,
            engine: engine,
            remote: remote,
            scheduler: scheduler,
            notifications: notifications,
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
        if case .server(_, 412) = error {
            #expect(pending[0].failureMessage?.contains("capacity") == true)
            #expect(try await fixture.store.read { try MutationQueueRecord.fetchAll($0).first?.lastError }
                == KanbanCreationFailure.rejected.rawValue)
        }
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
        #expect(pending[0].failureMessage?.contains("Column unavailable") == true)
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

    private func recovery(_ fixture: Fixture) -> OfflineKanbanCreationRecovery {
        OfflineKanbanCreationRecovery(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: fixture.scheduler,
        )
    }

    @Test(arguments: [false, true])
    func `capacity reserves the last slot and rejects another creation atomically`(online: Bool) async throws {
        let fixture = try await fixture(online: online)
        try await fixture.store.write { db in
            try db.execute(sql: "UPDATE kanbanBucket SET \"limit\" = 1 WHERE remoteID = 20")
        }
        async let first: VikunjaTask? = try? fixture.board.createTask(
            title: "First", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        async let second: VikunjaTask? = try? fixture.board.createTask(
            title: "Second", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        let results = await [first, second].compactMap(\.self)
        #expect(results.count == 1)
        await #expect(throws: VikunjaError.bucketFull) {
            try await fixture.board.createTask(title: "Third", projectID: .remote(1), viewID: 10, bucketID: 20)
        }
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 1)
        #expect(try await fixture.store.read { try KanbanAssignmentRecord.fetchCount($0) } == 1)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 1)
        #expect(await fixture.scheduler.calls == 1)
    }

    @Test func `online capacity rejection removes task dependencies and notifies once despite failed refresh`() async throws {
        let fixture = try await fixture(online: true)
        var task = try await fixture.board.createTask(
            title: "Rejected", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        task.description = "Edited before upload"
        _ = try await fixture.tasks.update(task)
        let comments = OfflineTaskCommentRepository(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: fixture.scheduler,
        )
        _ = try await comments.addComment("Keep no orphan", toTask: task.id)
        // A relation queued against another task must not retain a reference to the deleted local task.
        let other = try await fixture.board.createTask(title: "Other", projectID: .remote(1), viewID: 10, bucketID: 21)
        let relations = OfflineTaskRelationRepository(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: fixture.scheduler,
        )
        try await relations.addRelation(kind: .related, otherTaskID: task.id, toTask: other.id)
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.tasks.fetchTasks(projectID: .remote(1)).isEmpty)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try TaskCommentRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try KanbanAssignmentRecord.fetchCount($0) } == 0)
        #expect(await fixture.notifications.accounts == [fixture.accountID, fixture.accountID])
        #expect(await fixture.remote.downloadRequests == 2)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.count == 2)
    }

    @Test func `offline capacity rejection survives restart and redirects the same edited task`() async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(title: "Offline", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.requests.count == 1)
        #expect(await fixture.notifications.accounts.isEmpty)
        var edited = task
        edited.description = "Must survive"
        edited.priority = .high
        _ = try await fixture.tasks.update(edited)
        let reopened = try LocalStore(directory: fixture.directory)
        let pending = try #require(try await reopened.pendingSyncOperations(accountID: fixture.accountID).first)
        #expect(pending.canRecoverKanbanCreation)
        let recovery = OfflineKanbanCreationRecovery(
            localStore: reopened, accountID: fixture.accountID, syncRequester: fixture.scheduler,
        )
        let buckets = try await recovery.recoveryBuckets(operationID: pending.id)
        #expect(buckets.map(\.id) == [20, 21])
        try await recovery.retryCreation(operationID: pending.id, bucketID: 21)
        await fixture.remote.configure()
        try await fixture.engine.drainTaskMutations()
        let saved = try await fixture.tasks.fetchTask(id: task.id)
        #expect(saved.id == .remote(500))
        #expect(saved.description == "Must survive")
        #expect(saved.priority == .high)
        #expect(saved.isDone)
        #expect(await fixture.remote.requests.last?.1 == 21)
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 1)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test func `recovery excludes its own slot but rejects a full different destination`() async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(title: "Recover", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        _ = try await fixture.board.createTask(title: "Occupant", projectID: .remote(1), viewID: 10, bucketID: 21)
        try await fixture.store.write { db in
            try db.execute(sql: "UPDATE kanbanBucket SET \"limit\" = 1")
        }
        let pending = try #require(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
            .first { $0.canRecoverKanbanCreation })
        let recovery = recovery(fixture)
        let buckets = try await recovery.recoveryBuckets(operationID: pending.id)
        #expect(buckets.map(\.isFull) == [false, true])
        await #expect(throws: VikunjaError.bucketFull) {
            try await recovery.retryCreation(operationID: pending.id, bucketID: 21)
        }
        #expect(try await fixture.tasks.fetchTask(id: task.id).isDone == false)
        try await recovery.retryCreation(operationID: pending.id, bucketID: nil)
        let retried = try #require(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
            .first { $0.id == pending.id })
        #expect(retried.status == .pending)
        #expect(!retried.needsConflictResolution)
    }

    @Test func `explicit recovery and legacy creations never auto delete after rejection`() async throws {
        let fixture = try await fixture(online: true)
        let task = try await fixture.board.createTask(title: "Legacy", projectID: .remote(1), viewID: 10, bucketID: 20)
        try await fixture.store.write { db in
            var item = try #require(MutationQueueRecord.fetchAll(db).first)
            var payload = try KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: item)
            payload.kanbanCreatedOnline = nil
            item.payload = try KanbanLocalMutations.encode(payload)
            try item.update(db)
        }
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        let pending = try #require(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).first)
        try await recovery(fixture).retryCreation(operationID: pending.id, bucketID: nil)
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.tasks.fetchTask(id: task.id).title == "Legacy")
        #expect(await fixture.notifications.accounts.isEmpty)
        try await recovery(fixture).deleteRejectedCreation(operationID: pending.id)
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test func `unknown outcomes cannot be retried redirected or removed by capacity recovery`() async throws {
        let fixture = try await fixture(online: true)
        let task = try await fixture.board.createTask(title: "Unknown", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.configure(failure: .timeout)
        try await fixture.engine.drainTaskMutations()
        let pending = try #require(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).first)
        #expect(!pending.canRecoverKanbanCreation)
        await #expect(throws: VikunjaError.notFound) {
            try await recovery(fixture).retryCreation(operationID: pending.id, bucketID: 21)
        }
        await #expect(throws: VikunjaError.notFound) {
            try await recovery(fixture).deleteRejectedCreation(operationID: pending.id)
        }
        #expect(try await fixture.tasks.fetchTask(id: task.id).title == "Unknown")
        #expect(await fixture.notifications.accounts.isEmpty)
        #expect(await fixture.remote.requests.count == 1)
    }

    @Test func `recovery cannot read modify or delete another account's task`() async throws {
        let fixture = try await fixture()
        _ = try await fixture.board.createTask(title: "Scoped", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        let pending = try #require(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).first)
        let other = OfflineKanbanCreationRecovery(
            localStore: fixture.store, accountID: UUID(), syncRequester: fixture.scheduler,
        )
        await #expect(throws: VikunjaError.notFound) { try await other.recoveryBuckets(operationID: pending.id) }
        await #expect(throws: VikunjaError.notFound) {
            try await other.retryCreation(operationID: pending.id, bucketID: nil)
        }
        await #expect(throws: VikunjaError.notFound) { try await other.deleteRejectedCreation(operationID: pending.id) }
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 1)
    }

    @Test func `capacity rejection refreshes external occupancy and prevents the next local add`() async throws {
        let fixture = try await fixture(online: true)
        _ = try await fixture.board.createTask(title: "Race", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.setDownload(KanbanDownload(
            viewID: 10, mode: "manual", filterQuery: "", defaultBucketID: 20, doneBucketID: 21,
            buckets: [
                KanbanBucket(id: 20, title: "Full", limit: 1, tasks: [
                    VikunjaTask(id: 123, title: "Created from web", projectID: 1),
                ]),
                KanbanBucket(id: 21, title: "Done", isDoneBucket: true),
            ],
        ))
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        guard case let .available(board) = try await fixture.board.fetchBoard(projectID: .remote(1), viewID: 10)
        else { Issue.record("Missing refreshed board"); return }
        #expect(board.buckets[0].isFull)
        #expect(board.buckets[0].tasks.map(\.id) == [.remote(123)])
        await #expect(throws: VikunjaError.bucketFull) {
            try await fixture.board.createTask(title: "Blocked", projectID: .remote(1), viewID: 10, bucketID: 20)
        }
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test(arguments: [false, true])
    func `deleting during a capacity rejected upload leaves no orphan or notification`(online: Bool) async throws {
        let fixture = try await fixture(online: online)
        let task = try await fixture.board.createTask(title: "Delete", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.configure(failure: .bucketFull, hook: { try await fixture.tasks.delete(id: task.id) })
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
        #expect(try await fixture.store.read { try TaskRecord.fetchCount($0) } == 0)
        #expect(await fixture.notifications.accounts.isEmpty)
    }

    @Test func `failed recovery deletion rolls back both the local task and its queued creation`() async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(
            title: "Preserve", projectID: .remote(1), viewID: 10, bucketID: 20,
        )
        await fixture.remote.configure(failure: .bucketFull)
        try await fixture.engine.drainTaskMutations()
        let pending = try #require(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).first)
        try await fixture.store.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_test_delete BEFORE DELETE ON task
            BEGIN SELECT RAISE(ABORT, 'Simulated deletion failure'); END;
            """)
        }
        await #expect(throws: DatabaseError.self) {
            try await recovery(fixture).deleteRejectedCreation(operationID: pending.id)
        }
        #expect(try await fixture.tasks.fetchTask(id: task.id).title == "Preserve")
        let remaining = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(remaining.first?.canRecoverKanbanCreation == true)
        #expect(try await fixture.store.read { try KanbanAssignmentRecord.fetchCount($0) } == 1)
    }
}
