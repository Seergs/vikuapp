import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor FilterBoardRemote: BucketRepositoryProtocol {
    var tasks = [
        VikunjaTask(id: 11, title: "Work task", projectID: 1),
        VikunjaTask(id: 22, title: "Home task", projectID: 2),
    ]
    var failure: VikunjaError?
    var mode = "manual"
    func useAutomaticBuckets() {
        mode = "filter"
    }

    private(set) var requests: [(Int, Int?)] = []
    struct Move: Sendable {
        let taskID: Int
        let bucketID: Int
        let projectID: Int
        let viewID: Int?
    }

    private(set) var moves: [Move] = []
    func fail() {
        failure = .offline
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        requests.append((projectID, viewID))
        if let failure {
            throw failure
        }
        return KanbanDownload(
            viewID: 7, mode: mode, filterQuery: "priority >= 3", defaultBucketID: 10, doneBucketID: 20,
            buckets: [
                KanbanBucket(id: 10, title: "Todo", tasks: tasks.filter { !$0.isDone }),
                KanbanBucket(id: 20, title: "Done", isDoneBucket: true, tasks: tasks.filter(\.isDone)),
            ],
        )
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        try await downloadBoard(projectID: projectID, viewID: nil).buckets
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int, viewID: Int?) async throws -> VikunjaTask {
        if let failure {
            throw failure
        }
        moves.append(Move(taskID: taskID, bucketID: toBucketID, projectID: projectID, viewID: viewID))
        guard let index = tasks.firstIndex(where: { $0.id == .remote(taskID) }) else { throw VikunjaError.notFound }
        tasks[index].isDone = toBucketID == 20
        return tasks[index]
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        Issue.record("Saved filters must not create tasks without an owning project")
        throw VikunjaError.notFound
    }
}

struct OnlineSavedFilterKanbanTests {
    private struct Fixture {
        let store: LocalStore
        let accountID: UUID
        let remote: FilterBoardRemote
        let repository: OnlineSavedFilterKanbanRepository
    }

    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        try await store.write { db in
            for id in [1, 2, -2] {
                try ProjectRecord(
                    localID: UUID(), accountID: accountID, remoteID: id, title: "Project \(id)",
                    description: nil, isArchived: false, isFavorite: false, parentProjectLocalID: nil,
                    position: 0, hexColor: "", serverUpdatedAt: nil,
                ).insert(db)
            }
        }
        let remote = FilterBoardRemote()
        let repository = OnlineSavedFilterKanbanRepository(
            projectID: .remote(-2), localStore: store, accountID: accountID, transport: remote,
        )
        return Fixture(store: store, accountID: accountID, remote: remote, repository: repository)
    }

    private func board(_ repository: OnlineSavedFilterKanbanRepository) async throws -> KanbanBoard {
        let snapshot = try await repository.fetchBoard(projectID: .remote(-2), viewID: nil)
        guard case let .available(board) = snapshot else { throw VikunjaError.notFound }
        return board
    }

    @Test func `explicit refresh loads cross-project tasks without transferring ownership or persisting a board`() async throws {
        let fixture = try await fixture()
        let store = fixture.store
        let accountID = fixture.accountID
        let remote = fixture.remote
        let repository = fixture.repository
        #expect(try await repository.fetchBoard(projectID: .remote(-2), viewID: nil) == .unavailable)
        #expect(await remote.requests.isEmpty)
        try await repository.refresh(scope: .kanban(projectID: .remote(-2)))
        let loaded = try await board(repository)
        #expect(loaded.buckets.flatMap(\.tasks).map(\.projectID) == [.remote(1), .remote(2)])
        #expect(loaded.supportsWrites)
        #expect(!loaded.supportsTaskCreation)
        #expect(loaded.requiresConnection)
        #expect(await remote.requests.count == 1)
        try await store.read { db in
            let taskCount = try TaskRecord.fetchCount(db)
            let viewCount = try KanbanViewRecord.fetchCount(db)
            #expect(taskCount == 2)
            #expect(viewCount == 0)
        }
        let reopened = OnlineSavedFilterKanbanRepository(
            projectID: .remote(-2), localStore: store, accountID: accountID, transport: remote,
        )
        #expect(try await reopened.fetchBoard(projectID: .remote(-2), viewID: nil) == .unavailable)
        #expect(try await repository.fetchBoard(projectID: .remote(-3), viewID: nil) == .unavailable)
    }

    @Test func `online movement addresses the filter view and updates canonical completion`() async throws {
        let fixture = try await fixture()
        let store = fixture.store
        let remote = fixture.remote
        let repository = fixture.repository
        try await repository.prepare()
        let moved = try await repository.moveTask(taskID: .remote(22), projectID: .remote(-2), viewID: 7, bucketID: 20)
        #expect(moved.isDone)
        #expect(moved.projectID == .remote(2))
        let move = try #require(await remote.moves.first)
        #expect(move.taskID == 22 && move.bucketID == 20 && move.projectID == -2 && move.viewID == 7)
        #expect(try await board(repository).buckets.last?.tasks.map(\.id) == [.remote(22)])
        try await store.read { db in
            let task = try TaskRecord.filter(Column("remoteID") == 22).fetchOne(db)
            let queueCount = try MutationQueueRecord.fetchCount(db)
            #expect(task?.isDone == true)
            #expect(queueCount == 0)
        }
    }

    @Test func `offline writes fail without queuing and failed refresh preserves the visible snapshot`() async throws {
        let fixture = try await fixture()
        let store = fixture.store
        let remote = fixture.remote
        let repository = fixture.repository
        try await repository.prepare()
        await remote.fail()
        await #expect(throws: VikunjaError.offline) {
            try await repository.moveTask(taskID: .remote(11), projectID: .remote(-2), viewID: 7, bucketID: 20)
        }
        await #expect(throws: VikunjaError.offline) {
            try await repository.refresh(scope: .kanban(projectID: .remote(-2)))
        }
        #expect(try await board(repository).buckets.first?.tasks.count == 2)
        #expect(try await store.read { try MutationQueueRecord.fetchCount($0) } == 0)
    }

    @Test func `automatic boards remain readable but reject movements`() async throws {
        let fixture = try await fixture()
        await fixture.remote.useAutomaticBuckets()
        try await fixture.repository.prepare()
        #expect(try await !board(fixture.repository).supportsWrites)
        await #expect(throws: VikunjaError.notFound) {
            try await fixture.repository.moveTask(
                taskID: .remote(11), projectID: .remote(-2), viewID: 7, bucketID: 20,
            )
        }
        #expect(await fixture.remote.moves.isEmpty)
    }

    @Test func `a pending deletion stays hidden and cannot be resurrected by refresh`() async throws {
        let fixture = try await fixture()
        try await fixture.repository.prepare()
        let tasks = OfflineTaskRepository(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        try await tasks.delete(id: .remote(11))
        try await fixture.repository.refresh(scope: .kanban(projectID: .remote(-2)))
        let ids = try await board(fixture.repository).buckets.flatMap(\.tasks).map(\.id)
        #expect(ids == [.remote(22)])
        await #expect(throws: SyncIncompleteError.self) {
            try await fixture.repository.moveTask(
                taskID: .remote(11), projectID: .remote(-2), viewID: 7, bucketID: 20,
            )
        }
        #expect(await fixture.remote.moves.isEmpty)
    }

    @Test func `refresh preserves pending edits and online movement cannot bypass them`() async throws {
        let fixture = try await fixture()
        let store = fixture.store
        let accountID = fixture.accountID
        let remote = fixture.remote
        let repository = fixture.repository
        try await repository.prepare()
        try await store.write { db in
            var task = try #require(try TaskRecord.filter(Column("remoteID") == 11).fetchOne(db))
            task.title = "Offline edit"
            try task.update(db)
            var mutation = MutationQueueRecord(
                id: nil, accountID: accountID, entityType: .task, operation: .update, targetLocalID: task.localID,
                payload: nil, createdAt: Date(), retryCount: 0, lastError: nil, status: .pending,
                needsConflictResolution: false,
            )
            try mutation.insert(db)
        }
        try await repository.refresh(scope: .kanban(projectID: .remote(-2)))
        #expect(try await board(repository).buckets.first?.tasks.first?.title == "Offline edit")
        await #expect(throws: SyncIncompleteError.self) {
            try await repository.moveTask(taskID: .remote(11), projectID: .remote(-2), viewID: 7, bucketID: 20)
        }
        #expect(await remote.moves.isEmpty)
    }
}
