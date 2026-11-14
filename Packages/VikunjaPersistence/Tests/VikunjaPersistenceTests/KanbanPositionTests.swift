import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor PositionRemote: BucketRepositoryProtocol {
    var tasks = (100 ... 102).map { VikunjaTask(id: .remote($0), title: "Task \($0)", priority: .high, projectID: 1) }
    var positions: [Int: Double] = [100: 100, 101: 200, 102: 300]
    var buckets: [Int: Int] = [100: 20, 101: 20, 102: 20]
    var readFailure: VikunjaError?
    var writeFailure: VikunjaError?
    var failAfterWrite: VikunjaError?
    var renormalize = false
    var writeHook: (@Sendable () async throws -> Void)?
    private(set) var writes: [Int] = []

    func configure(
        read: VikunjaError? = nil,
        write: VikunjaError? = nil,
        afterWrite: VikunjaError? = nil,
        renormalize: Bool = false,
    ) {
        readFailure = read
        writeFailure = write
        failAfterWrite = afterWrite
        self.renormalize = renormalize
    }

    func onWrite(_ hook: (@Sendable () async throws -> Void)?) {
        writeHook = hook
    }

    func moveRemotely(_ id: Int, to bucket: Int) {
        buckets[id] = bucket
        if let index = tasks.firstIndex(where: { $0.id == .remote(id) }) {
            tasks[index].isDone = bucket == 21
        }
    }

    func fetchTask(_ id: EntityID) throws -> VikunjaTask {
        try #require(tasks.first { $0.id == id })
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        if let readFailure {
            throw readFailure
        }
        return KanbanDownload(
            viewID: 10,
            mode: "manual",
            filterQuery: "",
            defaultBucketID: 20,
            doneBucketID: 21,
            buckets: [20, 21].map { bucket in
                KanbanBucket(
                    id: bucket,
                    title: "Bucket",
                    isDoneBucket: bucket == 21,
                    tasks: tasks.filter {
                        buckets[$0.id.remoteValue ?? 0] == bucket
                    }
                    .sorted {
                        positions[$0.id.remoteValue ?? 0, default: 0] < positions[$1.id.remoteValue ?? 0, default: 0]
                    },
                )
            },
            taskPositions: positions,
        )
    }

    func setTaskPosition(taskID: Int, viewID: Int, position: Double) async throws -> TaskViewPosition {
        writes.append(taskID)
        if let writeFailure {
            throw writeFailure
        }
        positions[taskID] = position
        if renormalize {
            let sorted = positions.sorted { $0.value < $1.value }.map(\.key)
            for (index, id) in sorted.enumerated() {
                positions[id] = Double(index + 1) * 65536
            }
        }
        try await writeHook?()
        if let failAfterWrite {
            throw failAfterWrite
        }
        return TaskViewPosition(taskID: taskID, viewID: viewID, position: positions[taskID] ?? position)
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        try await downloadBoard(projectID: projectID, viewID: 10).buckets
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int, viewID: Int?) async throws -> VikunjaTask {
        throw VikunjaError.notFound
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        let created = VikunjaTask(id: 500, title: task.title, projectID: .remote(projectID))
        tasks.append(created)
        buckets[500] = bucketID
        positions[500] = 50
        return created
    }
}

struct KanbanPositionTests {
    @Test
    func `ordering stays scoped to its view even when the same task belongs to two views`() async throws {
        let fixture = try await fixture()
        try await fixture.store.write { db in
            let original = try #require(KanbanViewRecord.fetchAll(db).first)
            let view = KanbanViewRecord(
                localID: UUID(),
                accountID: fixture.accountID,
                projectLocalID: original.projectLocalID,
                remoteID: 11,
                mode: "manual",
                filterQuery: "",
                defaultBucketID: 30,
                lastCompletePullAt: Date(),
            )
            try view.insert(db)
            let bucket = KanbanBucketRecord(
                localID: UUID(),
                accountID: fixture.accountID,
                projectLocalID: original.projectLocalID,
                viewLocalID: view.localID,
                remoteID: 30,
                title: "Other view",
                position: 0,
                limit: 0,
                serverCount: 3,
            )
            try bucket.insert(db)
            let rows = try TaskRecord.fetchAll(db).sorted { ($0.remoteID ?? 0) < ($1.remoteID ?? 0) }
            for (index, row) in rows.enumerated() {
                try KanbanAssignmentRecord(
                    accountID: fixture.accountID,
                    projectLocalID: original.projectLocalID,
                    viewLocalID: view.localID,
                    bucketLocalID: bucket.localID,
                    taskLocalID: row.localID,
                    position: Double(index + 1) * 100,
                ).insert(db)
            }
        }
        try await reorder(fixture, .remote(102), .top)
        guard case let .available(other) = try await fixture.board.fetchBoard(projectID: 1, viewID: 11) else {
            Issue.record("Expected second cached view"); return
        }
        #expect(other.buckets[0].tasks.map(\.id) == [100, 101, 102])
        #expect(try await ids(fixture.board) == [102, 100, 101])
    }

    @Test
    func `a later bucket move supersedes an order tied to the old bucket`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        _ = try await fixture.board.moveTask(taskID: 102, projectID: 1, viewID: 10, bucketID: 21)
        let queued = try await fixture.store.read { try MutationQueueRecord.fetchAll($0) }
        #expect(queued.map(\.operation) == [.moveBucket])
        #expect(try await ids(fixture.board, bucketID: 21) == [102])
    }

    @Test(arguments: ["filter", "manual"])
    func `automatic and filtered cached views reject offline ordering`(mode: String) async throws {
        let fixture = try await fixture()
        try await fixture.store.write { db in
            var view = try #require(KanbanViewRecord.fetchAll(db).first)
            view.mode = mode
            view.filterQuery = mode == "manual" ? "priority >= 3" : ""
            try view.update(db)
        }
        await #expect(throws: VikunjaError.notFound) { try await reorder(fixture, .remote(102), .top) }
        #expect(try await ids(fixture.board) == [100, 101, 102])
    }

    @Test
    func `an acknowledged write whose refresh fails is not submitted again`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        await fixture.remote.onWrite { await fixture.remote.configure(read: .offline) }
        await #expect(throws: VikunjaError.offline) { try await fixture.engine.drainTaskMutations() }
        let queued = try await fixture.store.read { try #require(MutationQueueRecord.fetchAll($0).first) }
        #expect(try KanbanPositionLocalMutations.payload(queued).confirmed)
        #expect(try await ids(fixture.board) == [102, 100, 101])
        await fixture.remote.onWrite(nil)
        await fixture.remote.configure()
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.writes == [102])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `rejected writes retain a retryable operation and do not change unrelated fields`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        await fixture.remote.configure(write: .server(message: "Forbidden", statusCode: 403))
        try await fixture.engine.drainTaskMutations()
        let failed = try await fixture.store.read { try #require(MutationQueueRecord.fetchAll($0).first) }
        #expect(failed.status == .failed && !failed.needsConflictResolution)
        #expect(try KanbanPositionLocalMutations.payload(failed).submittedPosition == nil)
        #expect(try await ids(fixture.board) == [102, 100, 101])
        await fixture.remote.configure()
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
        #expect(fixture.taskRemote.updatedTasks.isEmpty)
    }

    private struct Fixture: Sendable {
        let store: LocalStore
        let directory: URL
        let accountID: UUID
        let board: OfflineKanbanBoardRepository
        let remote: PositionRemote
        let taskRemote: FakeTaskRepository
        let engine: SyncEngine
    }

    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        try await store.write { db in
            try ProjectRecord(
                localID: UUID(),
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
        }
        let remote = PositionRemote()
        let taskRemote = FakeTaskRepository()
        taskRemote.tasks = await remote.tasks
        taskRemote.fetchTaskResponse = { try await remote.fetchTask($0) }
        let engine = makeEngine(store: store, accountID: accountID, remote: remote, tasks: taskRemote)
        try await engine.pullKanban(projectID: .remote(1))
        return Fixture(
            store: store,
            directory: directory,
            accountID: accountID,
            board: OfflineKanbanBoardRepository(
                localStore: store,
                accountID: accountID,
                syncRequester: NoopKanbanSyncRequester(),
            ),
            remote: remote,
            taskRemote: taskRemote,
            engine: engine,
        )
    }

    private func makeEngine(
        store: LocalStore,
        accountID: UUID,
        remote: PositionRemote,
        tasks: FakeTaskRepository,
    ) -> SyncEngine {
        SyncEngine(
            localStore: store,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            taskRepository: tasks,
            relationRepository: FakeTaskRelationRepository(),
            accountID: accountID,
            bucketRepository: remote,
            capabilityProvider: KanbanCapabilities(),
        )
    }

    private func reorder(
        _ fixture: Fixture,
        _ taskID: EntityID,
        _ placement: KanbanTaskPlacement,
        bucketID: Int = 20,
    ) async throws {
        try await fixture.board.reorderTask(
            taskID: taskID,
            projectID: .remote(1),
            viewID: 10,
            bucketID: bucketID,
            placement: placement,
        )
    }

    private func ids(_ repository: OfflineKanbanBoardRepository, bucketID: Int = 20) async throws -> [EntityID] {
        guard case let .available(board) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Expected cached board"); return []
        }
        return board.buckets.first { $0.id == bucketID }?.tasks.map(\.id) ?? []
    }

    @Test
    func `offline edge commands persist ordering without changing task fields and survive reopening`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        #expect(try await ids(fixture.board) == [102, 100, 101])
        #expect(await fixture.remote.writes.isEmpty)
        let reopened = try LocalStore(directory: fixture.directory)
        let reader = OfflineKanbanBoardRepository(
            localStore: reopened,
            accountID: fixture.accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await ids(reader) == [102, 100, 101])
        try await fixture.store.read { db in
            let tasks = try TaskRecord.filter(Column("accountID") == fixture.accountID).fetchAll(db)
            #expect(tasks.allSatisfy { !$0.isDone && $0.priority == VikunjaTask.Priority.high.rawValue })
            let pending = try PendingSyncOperationsReader.operations(accountID: fixture.accountID, db: db)
            #expect(pending.count == 1)
            #expect(pending.first?.action == .update)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(try await ids(fixture.board) == [102, 100, 101])
        #expect(await fixture.remote.writes == [102])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
        #expect(fixture.taskRemote.updatedTasks.isEmpty)
    }

    @Test
    func `coalescing retains the chronology of repeated commands on different tasks`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        try await reorder(fixture, .remote(101), .top)
        try await reorder(fixture, .remote(102), .top)
        #expect(try await ids(fixture.board) == [102, 101, 100])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 2)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.writes == [101, 102])
        #expect(try await ids(fixture.board) == [102, 101, 100])
    }

    @Test
    func `server normalization updates the whole numeric scale without losing newer local orders`() async throws {
        let fixture = try await fixture()
        await fixture.remote.configure(renormalize: true)
        try await reorder(fixture, .remote(102), .top)
        await fixture.remote.onWrite {
            try await fixture.board.moveTaskToTop(taskID: 100, projectID: 1, viewID: 10, bucketID: 20)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(try await ids(fixture.board) == [100, 102, 101])
        await fixture.remote.onWrite(nil)
        try await fixture.engine.drainTaskMutations()
        #expect(try await ids(fixture.board) == [100, 102, 101])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `offline preflight retains pending intent and reconnect drains it`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        await fixture.remote.configure(read: .offline)
        await #expect(throws: VikunjaError.offline) { try await fixture.engine.drainTaskMutations() }
        #expect(try await ids(fixture.board) == [102, 100, 101])
        let queued = try await fixture.store.read { try #require(MutationQueueRecord.fetchAll($0).first) }
        #expect(queued.retryCount == 0 && queued.status == .pending)
        await fixture.remote.configure()
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.writes == [102])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `a lost write response is reconciled without sending the command twice`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        await fixture.remote.configure(afterWrite: .timeout, renormalize: true)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.writes == [102])
        await fixture.remote.configure()
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.writes == [102])
        #expect(try await ids(fixture.board) == [102, 100, 101])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `interrupted in flight intent is recovered after restart without duplicate writes`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(100), .bottom)
        await fixture.remote.onWrite { throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await fixture.engine.drainTaskMutations() }
        await fixture.remote.onWrite(nil)
        let replacement = makeEngine(
            store: fixture.store,
            accountID: fixture.accountID,
            remote: fixture.remote,
            tasks: fixture.taskRemote,
        )
        try await replacement.drainTaskMutations()
        #expect(await fixture.remote.writes == [100])
        #expect(try await ids(fixture.board) == [101, 102, 100])
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `remote bucket changes become visible conflicts and discarding adopts known server placement`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(102), .top)
        await fixture.remote.moveRemotely(102, to: 21)
        try await fixture.engine.drainTaskMutations()
        let conflict = try await fixture.store.read { try #require(MutationQueueRecord.fetchAll($0).first) }
        #expect(conflict.needsConflictResolution)
        #expect(await fixture.remote.writes.isEmpty)
        try await fixture.store.discardConflictedPendingSyncOperation(
            id: #require(conflict.id),
            accountID: fixture.accountID,
        )
        #expect(try await ids(fixture.board, bucketID: 21) == [102])
        let task = try await OfflineTaskRepository(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: NoopKanbanSyncRequester(),
        ).fetchTask(id: 102)
        #expect(task.isDone)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `unsynced tasks wait for their identity before sending positions`() async throws {
        let fixture = try await fixture()
        let created = try await fixture.board.createTask(title: "Local", projectID: 1, viewID: 10, bucketID: 20)
        try await reorder(fixture, created.id, .bottom)
        #expect(try await ids(fixture.board).last == created.id)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.writes == [500])
        #expect(try await ids(fixture.board).last == .remote(500))
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test
    func `edge no ops and invalid account or bucket do not queue writes`() async throws {
        let fixture = try await fixture()
        try await reorder(fixture, .remote(100), .top)
        #expect(try await fixture.store.read { try MutationQueueRecord.fetchCount($0) } == 0)
        await #expect(throws: VikunjaError.notFound) { try await reorder(fixture, .remote(100), .top, bucketID: 21) }
        let other = OfflineKanbanBoardRepository(
            localStore: fixture.store,
            accountID: UUID(),
            syncRequester: NoopKanbanSyncRequester(),
        )
        await #expect(throws: VikunjaError.notFound) {
            try await other.moveTaskToBottom(taskID: 100, projectID: 1, viewID: 10, bucketID: 20)
        }
        #expect(try await ids(fixture.board) == [100, 101, 102])
    }
}
