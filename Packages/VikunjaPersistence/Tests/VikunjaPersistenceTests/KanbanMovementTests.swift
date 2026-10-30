import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor MovingKanbanRemote: BucketRepositoryProtocol {
    var tasks = [100: VikunjaTask(
        id: 100,
        title: "Task",
        projectID: 1,
        updated: Date(timeIntervalSince1970: 1_700_000_000),
    )]
    var placements = [100: 20]
    var availableBuckets = [20, 21, 22]
    var moveHook: (@Sendable () async throws -> Void)?
    var createHook: (@Sendable () async throws -> Void)?
    var readHook: (@Sendable () async throws -> Void)?
    var failure: VikunjaError?
    var recurring = false
    private(set) var moved: [Int] = []
    private(set) var created: [Int] = []

    func setMoveHook(_ hook: (@Sendable () async throws -> Void)?) {
        moveHook = hook
    }

    func setCreateHook(_ hook: (@Sendable () async throws -> Void)?) {
        createHook = hook
    }

    func setReadHook(_ hook: (@Sendable () async throws -> Void)?) {
        readHook = hook
    }

    func setFailure(_ error: VikunjaError?) {
        failure = error
    }

    func removeDestination() {
        availableBuckets = [20, 21]
    }

    func setRecurring() {
        recurring = true
    }

    func setPlacement(_ bucketID: Int) {
        placements[100] = bucketID
        tasks[100]?.isDone = bucketID == 22
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        let buckets = availableBuckets.map { id in
            KanbanBucket(
                id: id,
                title: "Column",
                isDoneBucket: id == 22,
                tasks: tasks.filter { placements[$0.key] == id }.map(\.value),
            )
        }
        let result = KanbanDownload(
            viewID: 10,
            mode: "manual",
            filterQuery: "",
            defaultBucketID: 20,
            doneBucketID: 22,
            buckets: buckets,
        )
        try await readHook?()
        return result
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        try await downloadBoard(projectID: projectID, viewID: nil).buckets
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        created.append(bucketID)
        let result = VikunjaTask(id: .remote(500), title: task.title, isDone: task.isDone, projectID: task.projectID)
        placements[500] = bucketID
        tasks[500] = result
        try await createHook?()
        return result
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int, viewID: Int?) async throws -> VikunjaTask {
        #expect(viewID == 10)
        moved.append(toBucketID)
        if let failure, case .server = failure {
            throw failure
        }
        var task = try #require(tasks[taskID])
        task.isDone = toBucketID == 22
        task.updated = Date()
        placements[taskID] = recurring && toBucketID == 22 ? 20 : toBucketID
        if recurring {
            task.isDone = false
        }
        tasks[taskID] = task
        try await moveHook?()
        if let failure {
            throw failure
        }
        return task
    }
}

struct KanbanMovementTests {
    private struct Fixture: Sendable {
        let store: LocalStore
        let directory: URL
        let accountID: UUID
        let board: OfflineKanbanBoardRepository
        let tasks: OfflineTaskRepository
        let taskRemote: FakeTaskRepository
        let remote: MovingKanbanRemote
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
        let remote = MovingKanbanRemote()
        let taskRemote = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            taskRepository: taskRemote,
            relationRepository: FakeTaskRelationRepository(),
            accountID: accountID,
            bucketRepository: remote,
            capabilityProvider: KanbanCapabilities(),
        )
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
            tasks: OfflineTaskRepository(
                localStore: store,
                accountID: accountID,
                syncRequester: NoopKanbanSyncRequester(),
            ),
            taskRemote: taskRemote,
            remote: remote,
            engine: engine,
        )
    }

    @discardableResult
    private func move(_ fixture: Fixture, to bucketID: Int, taskID: EntityID = .remote(100)) async throws -> VikunjaTask {
        try await fixture.board.moveTask(taskID: taskID, projectID: .remote(1), viewID: 10, bucketID: bucketID)
    }

    private func queue(_ fixture: Fixture) async throws -> [MutationQueueRecord] {
        try await fixture.store.read { try MutationQueueRecord.fetchAll($0) }
    }

    private func location(_ fixture: Fixture, taskID: EntityID = .remote(100)) async throws -> Int? {
        guard case let .available(board) = try await fixture.board.fetchBoard(projectID: .remote(1), viewID: 10) else {
            return nil
        }
        return board.buckets.first { $0.tasks.contains { $0.id == taskID } }?.id
    }

    @Test func `no op coalescing completion and restart`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 20)
        #expect(try await queue(fixture).isEmpty)
        try await move(fixture, to: 21)
        let completed = try await move(fixture, to: 22)
        #expect(completed.isDone)
        #expect(try await fixture.tasks.fetchTask(id: .remote(100)).isDone)
        #expect(try await queue(fixture).count == 1)
        let reopened = try LocalStore(directory: fixture.directory)
        let repository = OfflineKanbanBoardRepository(
            localStore: reopened,
            accountID: fixture.accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        guard case let .available(board) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Missing cached board"); return
        }
        #expect(board.buckets[2].tasks.map(\.id) == [.remote(100)])
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved == [22])
        #expect(try await queue(fixture).isEmpty)
        let reopenedTask = try await move(fixture, to: 21)
        #expect(!reopenedTask.isDone)
    }

    @Test func `local creation movement folds into one post`() async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(title: "Local", projectID: .remote(1), viewID: 10, bucketID: 20)
        try await move(fixture, to: 22, taskID: task.id)
        #expect(try await queue(fixture).map(\.operation) == [.create])
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.created == [22])
        #expect(await fixture.remote.moved.isEmpty)
        #expect(try await location(fixture, taskID: .remote(500)) == 22)
    }

    @Test func `movement during creation waits for remote identity`() async throws {
        let fixture = try await fixture()
        let task = try await fixture.board.createTask(title: "Local", projectID: .remote(1), viewID: 10, bucketID: 20)
        await fixture.remote.setCreateHook {
            try await fixture.board.moveTask(taskID: task.id, projectID: .remote(1), viewID: 10, bucketID: 22)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).map(\.operation) == [.moveBucket])
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.created == [20])
        #expect(await fixture.remote.moved == [22])
        #expect(try await location(fixture, taskID: .remote(500)) == 22)
    }

    @Test func `old response does not overwrite newer move or completion`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 21)
        await fixture.remote.setMoveHook {
            _ = try await fixture.board.moveTask(taskID: .remote(100), projectID: .remote(1), viewID: 10, bucketID: 22)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(try await location(fixture) == 22)
        #expect(try await fixture.tasks.fetchTask(id: .remote(100)).isDone)
        #expect(try await queue(fixture).count == 1)
        await fixture.remote.setMoveHook(nil)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved == [21, 22])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `detail completion supersedes queued and in flight movement`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 21)
        await fixture.remote.setMoveHook {
            var task = try await fixture.tasks.fetchTask(id: .remote(100))
            task.isDone = true
            _ = try await fixture.tasks.update(task)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(try await location(fixture) == 22)
        #expect(try await queue(fixture).map(\.operation) == [.update])
        await fixture.remote.setMoveHook(nil)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.taskRemote.updatedTasks.first?.isDone == true)
        var task = try await fixture.tasks.fetchTask(id: .remote(100))
        task.isDone = false
        _ = try await fixture.tasks.update(task)
        #expect(try await location(fixture) == 20)
    }

    @Test func `atomic failure rolls back position and completion`() async throws {
        let fixture = try await fixture()
        try await fixture.store.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_move BEFORE INSERT ON mutationQueueItem
            WHEN NEW.operation = 'moveBucket'
            BEGIN SELECT RAISE(ABORT, 'Simulated failure'); END;
            """)
        }
        await #expect(throws: DatabaseError.self) { try await move(fixture, to: 22) }
        #expect(try await location(fixture) == 20)
        #expect(try await fixture.tasks.fetchTask(id: .remote(100)).isDone == false)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `downloaded snapshot and delayed snapshot preserve local intent`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 21)
        try await fixture.engine.pullKanban(projectID: .remote(1))
        #expect(try await location(fixture) == 21)
        await fixture.remote.setReadHook {
            _ = try await fixture.board.moveTask(taskID: .remote(100), projectID: .remote(1), viewID: 10, bucketID: 22)
        }
        await #expect(throws: VikunjaError.self) { try await fixture.engine.pullKanban(projectID: .remote(1)) }
        #expect(try await location(fixture) == 22)
    }

    @Test func `concurrent remote movement requires an explicit new choice`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 22)
        await fixture.remote.setPlacement(21)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved.isEmpty)
        #expect(try await queue(fixture).first?.needsConflictResolution == true)
        #expect(try await location(fixture) == 22)
        try await move(fixture, to: 20)
        try await move(fixture, to: 22)
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved == [22])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test(arguments: [VikunjaError.timeout, .server(message: "Full", statusCode: 412)])
    func `rejected and unconfirmed moves remain visible without replay`(error: VikunjaError) async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 22)
        await fixture.remote.setFailure(error)
        try await fixture.engine.drainTaskMutations()
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved == [22])
        let pending = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(pending.first?.failureMessage != nil)
        #expect(pending.first?.action == .moveBucket)
        #expect(try await location(fixture) == 22)
    }

    @Test func `deletion during movement does not leave orphaned work`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 21)
        await fixture.remote.setMoveHook { try await fixture.tasks.delete(id: .remote(100)) }
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).map(\.operation) == [.delete])
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).isEmpty)
        #expect(try await fixture.tasks.fetchTasks(projectID: .remote(1)).isEmpty)
    }

    @Test func `deleted destination and deletion before upload do not send moves`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 22)
        await fixture.remote.removeDestination()
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved.isEmpty)
        #expect(try await queue(fixture).first?.needsConflictResolution == true)
        try await fixture.tasks.delete(id: .remote(100))
        #expect(try await queue(fixture).map(\.operation) == [.delete])
        try await fixture.engine.drainTaskMutations()
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `recurring response uses server completion and default placement`() async throws {
        let fixture = try await fixture()
        await fixture.remote.setRecurring()
        try await move(fixture, to: 22)
        try await fixture.engine.drainTaskMutations()
        #expect(try await location(fixture) == 20)
        #expect(try await fixture.tasks.fetchTask(id: .remote(100)).isDone == false)
    }

    @Test func `edit during movement rebases against our own server write`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 21)
        await fixture.remote.setMoveHook {
            var task = try await fixture.tasks.fetchTask(id: .remote(100))
            task.title = "Edited during movement"
            _ = try await fixture.tasks.update(task)
        }
        try await fixture.engine.drainTaskMutations()
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.taskRemote.updatedTasks.map(\.title) == ["Edited during movement"])
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `detail completion uses recurring server response`() async throws {
        let fixture = try await fixture()
        var task = try await fixture.tasks.fetchTask(id: .remote(100))
        task.isDone = true
        _ = try await fixture.tasks.update(task)
        var nextOccurrence = task
        nextOccurrence.isDone = false
        nextOccurrence.dueDate = Date(timeIntervalSince1970: 1_900_000_000)
        fixture.taskRemote.updateResponse = nextOccurrence
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.tasks.fetchTask(id: .remote(100)).isDone == false)
        #expect(try await location(fixture) == 20)
        #expect(try await queue(fixture).isEmpty)
    }

    @Test func `changing project cancels unsent movements`() async throws {
        let fixture = try await fixture()
        try await move(fixture, to: 21)
        try await fixture.store.write { db in
            try ProjectRecord(
                localID: UUID(),
                accountID: fixture.accountID,
                remoteID: 2,
                title: "Other",
                description: nil,
                isArchived: false,
                isFavorite: false,
                parentProjectLocalID: nil,
                position: 0,
                hexColor: "",
                serverUpdatedAt: nil,
            ).insert(db)
        }
        var task = try await fixture.tasks.fetchTask(id: .remote(100))
        task.projectID = .remote(2)
        _ = try await fixture.tasks.update(task)
        #expect(try await queue(fixture).map(\.operation) == [.update])
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved.isEmpty)
    }

    @Test func `invalid boundaries and interrupted movement are safe`() async throws {
        let fixture = try await fixture()
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.board.moveTask(taskID: .remote(100), projectID: .remote(2), viewID: 10, bucketID: 22)
        }
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.board.moveTask(taskID: .remote(100), projectID: .remote(1), viewID: 99, bucketID: 22)
        }
        try await move(fixture, to: 21)
        try await fixture.store.write { db in
            var item = try #require(MutationQueueRecord.fetchAll(db).first)
            item.status = .inFlight
            try item.update(db)
        }
        try await fixture.engine.drainTaskMutations()
        #expect(await fixture.remote.moved.isEmpty)
        #expect(try await queue(fixture).first?.status == .failed)
    }
}
