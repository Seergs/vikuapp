import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

actor KanbanDownloadFake: BucketRepositoryProtocol {
    var result: KanbanDownload
    var failure: VikunjaError?
    private(set) var calls = 0
    var delay = false
    func slowDown() {
        delay = true
    }

    init(_ result: KanbanDownload) {
        self.result = result
    }

    func set(_ result: KanbanDownload) {
        self.result = result; failure = nil
    }

    func fail() {
        failure = .offline
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        calls += 1
        if delay {
            try await Task.sleep(for: .milliseconds(100))
        }
        if let failure {
            throw failure
        }
        return result
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        result.buckets
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int) async throws -> VikunjaTask {
        throw VikunjaError.notFound
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        throw VikunjaError.notFound
    }
}

struct KanbanCapabilities: CapabilityProvider {
    var enabled = true
    func serverInfo() async throws -> VikunjaServerInfo {
        throw VikunjaError.notFound
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        enabled
    }
}

struct KanbanSyncTests {
    private func board(_ tasks: [VikunjaTask], bucketID: Int = 20, viewID: Int = 10) -> KanbanDownload {
        KanbanDownload(
            viewID: viewID,
            mode: "manual",
            filterQuery: "",
            defaultBucketID: bucketID,
            doneBucketID: nil,
            buckets: [KanbanBucket(id: bucketID, title: "Todo", tasks: tasks)],
        )
    }

    private func engine(
        _ store: LocalStore,
        accountID: UUID,
        remote: KanbanDownloadFake,
        enabled: Bool = true,
    ) -> SyncEngine {
        SyncEngine(
            localStore: store,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(),
            accountID: accountID,
            bucketRepository: remote,
            capabilityProvider: KanbanCapabilities(enabled: enabled),
        )
    }

    private func project(_ store: LocalStore, accountID: UUID) async throws -> UUID {
        let id = UUID()
        try await store.write { db in
            try ProjectRecord(
                localID: id,
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
        return id
    }

    @Test func `download refresh failure and empty snapshot`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        _ = try await project(store, accountID: accountID)
        let remote = KanbanDownloadFake(board([VikunjaTask(id: 100, title: "Server", projectID: 1)]))
        let sync = engine(store, accountID: accountID, remote: remote)
        let repository = OfflineKanbanBoardRepository(localStore: store, accountID: accountID)
        try await sync.pullKanban(projectID: .remote(1))
        let original = try await repository.fetchBoard(projectID: .remote(1), viewID: 10)
        await remote.fail()
        await #expect(throws: VikunjaError.offline) { try await sync.pullKanban(projectID: .remote(1)) }
        #expect(try await repository.fetchBoard(projectID: .remote(1), viewID: 10) == original)
        await remote.set(board([]))
        try await sync.pullKanban(projectID: .remote(1))
        guard case let .available(empty) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Expected downloaded snapshot"); return
        }
        #expect(empty.buckets[0].tasks.isEmpty)
        #expect(try await store.read { try TaskRecord.fetchCount($0) } == 1)
    }

    @Test func `pending edits placements and deletes are preserved`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        _ = try await project(store, accountID: accountID)
        let remote = KanbanDownloadFake(board([VikunjaTask(id: 100, title: "Server", projectID: 1)]))
        let sync = engine(store, accountID: accountID, remote: remote)
        try await sync.pullKanban(projectID: .remote(1))
        let localID = try await store.write { db in
            var task = try #require(TaskRecord.fetchAll(db).first)
            task.title = "Local edit"
            try task.update(db)
            var mutation = MutationQueueRecord(
                id: nil,
                accountID: accountID,
                entityType: .task,
                operation: .update,
                targetLocalID: task.localID,
                payload: nil,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try mutation.insert(db)
            return task.localID
        }
        await remote.set(board([VikunjaTask(id: 100, title: "Remote edit", projectID: 1)], bucketID: 21))
        await #expect(throws: VikunjaError.notFound) { try await sync.pullKanban(projectID: .remote(1)) }
        #expect(try await store.read { try TaskRecord.fetchOne($0, key: localID)?.title } == "Local edit")
        #expect(try await store.read { try KanbanBucketRecord.fetchAll($0).map(\.remoteID).sorted() } == [20])
        try await store.write { db in
            var mutation = try #require(MutationQueueRecord.fetchAll(db).first)
            mutation.operation = .delete
            try mutation.update(db)
        }
        try await sync.pullKanban(projectID: .remote(1))
        #expect(try await store.read { try KanbanAssignmentRecord.fetchCount($0) } == 0)
        #expect(try await store.read { try TaskRecord.fetchCount($0) } == 1)
    }

    @Test func `local creation and other account survive refresh`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        _ = try await project(store, accountID: accountID)
        let remote = KanbanDownloadFake(board([]))
        let sync = engine(store, accountID: accountID, remote: remote)
        try await sync.pullKanban(projectID: .remote(1))
        let otherID = UUID()
        _ = try await project(store, accountID: otherID)
        try await engine(store, accountID: otherID, remote: remote).pullKanban(projectID: .remote(1))
        let localID = UUID()
        try await store.write { db in
            let view = try #require(KanbanViewRecord.fetchAll(db).first { $0.accountID == accountID })
            let bucket = try #require(KanbanBucketRecord.fetchAll(db).first { $0.accountID == accountID })
            try TaskRecord(
                localID: localID,
                accountID: accountID,
                remoteID: nil,
                title: "Offline create",
                description: nil,
                isDone: false,
                dueDate: nil,
                priority: 0,
                projectLocalID: view.projectLocalID,
                serverUpdatedAt: nil,
            ).insert(db)
            try KanbanAssignmentRecord(
                accountID: accountID,
                projectLocalID: view.projectLocalID,
                viewLocalID: view.localID,
                bucketLocalID: bucket.localID,
                taskLocalID: localID,
                position: 0,
            ).insert(db)
            var mutation = MutationQueueRecord(
                id: nil,
                accountID: accountID,
                entityType: .task,
                operation: .create,
                targetLocalID: localID,
                payload: nil,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try mutation.insert(db)
        }
        try await sync.pullKanban(projectID: .remote(1))
        let repository = OfflineKanbanBoardRepository(localStore: store, accountID: accountID)
        guard case let .available(snapshot) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Missing board"); return
        }
        #expect(snapshot.buckets[0].tasks.map(\.id) == [.local(localID)])
        #expect(try await store.read { try KanbanViewRecord.fetchCount($0) } == 2)
    }

    @Test func `unsupported server makes no board requests and invalid snapshot rolls back`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        _ = try await project(store, accountID: accountID)
        let remote = KanbanDownloadFake(board([VikunjaTask(id: 100, title: "Wrong project", projectID: 2)]))
        try await engine(store, accountID: accountID, remote: remote, enabled: false).pullKanban(projectID: .remote(1))
        #expect(await remote.calls == 0)
        await #expect(throws: VikunjaError.self) {
            try await engine(store, accountID: accountID, remote: remote).pullKanban(projectID: .remote(1))
        }
        #expect(try await store.read { try KanbanViewRecord.fetchCount($0) } == 0)
        #expect(try await store.read { try TaskRecord.fetchCount($0) } == 0)
        await #expect(throws: VikunjaError.notFound) {
            try await engine(store, accountID: UUID(), remote: remote).pullKanban(projectID: .remote(1))
        }
        #expect(await remote.calls == 1)
    }
}
