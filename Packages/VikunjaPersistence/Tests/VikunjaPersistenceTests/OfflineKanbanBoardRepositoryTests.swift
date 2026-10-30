import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct OfflineKanbanBoardRepositoryTests {
    private struct Fixture: Sendable {
        let project: ProjectRecord
        let task: TaskRecord
        let view: KanbanViewRecord
        let bucket: KanbanBucketRecord
        let assignment: KanbanAssignmentRecord
    }

    private func seed(_ store: LocalStore, accountID: UUID = UUID(), complete: Bool = true) async throws -> Fixture {
        let project = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Work", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0,
            hexColor: "", serverUpdatedAt: nil,
        )
        let task = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: nil, title: "Local task", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: project.localID, serverUpdatedAt: nil,
        )
        let view = KanbanViewRecord(
            localID: UUID(), accountID: accountID, projectLocalID: project.localID, remoteID: 10,
            mode: "manual", filterQuery: "", defaultBucketID: 20, doneBucketID: 20,
            lastCompletePullAt: complete ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
        )
        let bucket = KanbanBucketRecord(
            localID: UUID(), accountID: accountID, projectLocalID: project.localID,
            viewLocalID: view.localID, remoteID: 20, title: "Done", position: 1, limit: 4, serverCount: 1,
        )
        let assignment = KanbanAssignmentRecord(
            accountID: accountID, projectLocalID: project.localID, viewLocalID: view.localID,
            bucketLocalID: bucket.localID, taskLocalID: task.localID, position: 1,
        )
        try await store.write { db in
            try project.insert(db)
            try task.insert(db)
            try view.insert(db)
            try bucket.insert(db)
            try assignment.insert(db)
        }
        return Fixture(project: project, task: task, view: view, bucket: bucket, assignment: assignment)
    }

    @Test func `canonical task and placement survive reopening and remote identity`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let fixture = try await seed(store)
        let repository = OfflineKanbanBoardRepository(
            localStore: store, accountID: fixture.project.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        guard case let .available(initial) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Expected cached board"); return
        }
        #expect(initial.buckets[0].tasks[0].id == .local(fixture.task.localID))
        #expect(initial.buckets[0].limit == 4)
        #expect(initial.buckets[0].isDoneBucket)
        #expect(initial.supportsOfflineWrites)
        try await store.write { db in
            var row = fixture.task
            row.remoteID = 100
            row.title = "Edited in List"
            row.isDone = true
            try row.update(db)
        }
        let reopened = try LocalStore(directory: directory)
        let reader = OfflineKanbanBoardRepository(
            localStore: reopened, accountID: fixture.project.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        let snapshot = try await reader.fetchBoard(projectID: .local(fixture.project.localID), viewID: 10)
        guard case let .available(board) = snapshot else {
            Issue.record("Expected persisted board"); return
        }
        #expect(board.buckets[0].tasks[0].id == .remote(100))
        #expect(board.buckets[0].tasks[0].title == "Edited in List")
        #expect(board.buckets[0].tasks[0].isDone == true)
    }

    @Test func `missing snapshot differs from downloaded empty board`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let fixture = try await seed(store, complete: false)
        let repository = OfflineKanbanBoardRepository(
            localStore: store, accountID: fixture.project.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await repository.fetchBoard(projectID: .remote(1), viewID: 10) == .unavailable)
        try await store.write { db in
            try fixture.task.delete(db)
            var view = fixture.view
            view.lastCompletePullAt = Date()
            view.mode = "filter"
            try view.update(db)
        }
        guard case let .available(board) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Expected downloaded empty board"); return
        }
        #expect(board.buckets[0].tasks.isEmpty)
        #expect(!board.supportsOfflineWrites)
    }

    @Test func `foreign keys reject cross account and cross view assignments and cascade deletion`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let first = try await seed(store)
        let second = try await seed(store)
        await #expect(throws: DatabaseError.self) {
            try await store.write { db in
                var invalid = first.assignment
                invalid.taskLocalID = second.task.localID
                try invalid.insert(db)
            }
        }
        await #expect(throws: DatabaseError.self) {
            try await store.write { db in
                var invalid = first.assignment
                invalid.viewLocalID = second.view.localID
                try invalid.insert(db)
            }
        }
        #expect(try await OfflineKanbanBoardRepository(
            localStore: store, accountID: UUID(), syncRequester: NoopKanbanSyncRequester(),
        )
        .fetchBoard(projectID: .remote(1), viewID: 10) == .unavailable)
        try await store.write { db in try first.project.delete(db) }
        let counts = try await store.read { db in
            try (
                KanbanViewRecord.fetchCount(db), KanbanBucketRecord.fetchCount(db),
                KanbanAssignmentRecord.fetchCount(db),
            )
        }
        #expect(counts.0 == 1 && counts.1 == 1 && counts.2 == 1)
    }

    @Test func `bucket ordering filters and project moves`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let fixture = try await seed(store)
        try await store.write { db in
            var bucket = fixture.bucket
            bucket.localID = UUID()
            bucket.remoteID = 21
            bucket.position = 0
            try bucket.insert(db)
            var view = fixture.view
            view.filterQuery = "done = false"
            try view.update(db)
        }
        let repository = OfflineKanbanBoardRepository(
            localStore: store, accountID: fixture.project.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        guard case let .available(board) = try await repository.fetchBoard(projectID: .remote(1), viewID: 10) else {
            Issue.record("Missing board"); return
        }
        #expect(board.buckets.map(\.id) == [21, 20])
        #expect(!board.supportsOfflineWrites)
        try await store.write { db in
            var project = fixture.project
            project.localID = UUID()
            project.remoteID = 2
            try project.insert(db)
            var task = fixture.task
            task.projectLocalID = project.localID
            try task.update(db)
        }
        #expect(try await store.read { try KanbanAssignmentRecord.fetchCount($0) } == 0)
        #expect(try await store.read { try TaskRecord.fetchCount($0) } == 1)
    }

    @Test func `board changes emit account observation`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let fixture = try await seed(store)
        let stream = await store.observeChanges(accountID: fixture.project.accountID)
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        try await store.write { db in
            var bucket = fixture.bucket
            bucket.title = "Renamed"
            try bucket.update(db)
        }
        let change = try await iterator.next()
        #expect(change != nil)
    }

    @Test func `additive migration preserves existing tasks`() throws {
        let db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(on: &migrator)
        try migrator.migrate(db, upTo: "createVirtualProjectTask")
        let accountID = UUID()
        let projectID = UUID()
        try db.write { db in
            try ProjectRecord(
                localID: projectID, accountID: accountID, remoteID: 1, title: "Existing", description: nil,
                isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0,
                hexColor: "", serverUpdatedAt: nil,
            ).insert(db)
            try TaskRecord(
                localID: UUID(), accountID: accountID, remoteID: 1, title: "Keep me", description: nil,
                isDone: false, dueDate: nil, priority: 0, projectLocalID: projectID, serverUpdatedAt: nil,
            ).insert(db)
        }
        try migrator.migrate(db)
        #expect(try db.read { try TaskRecord.fetchAll($0).map(\.title) } == ["Keep me"])
    }
}
