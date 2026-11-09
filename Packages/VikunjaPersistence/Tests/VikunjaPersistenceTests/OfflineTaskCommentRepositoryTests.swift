import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor FakeCommentReachabilityMonitor: ReachabilityMonitoring {
    var isReachable: Bool

    init(isReachable: Bool) {
        self.isReachable = isReachable
    }

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

struct OfflineTaskCommentRepositoryTests {
    private struct Fixture {
        let repository: OfflineTaskCommentRepository
        let store: LocalStore
        let storeDirectory: URL
        let network: FakeTaskCommentRepository
        let projectLocalID: UUID
        let accountID: UUID
        let engine: SyncEngine
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func localID(of id: EntityID) -> UUID? {
        if case let .local(value) = id {
            return value
        }
        return nil
    }

    private func makeRepository(
        online: Bool,
        accountID: UUID = UUID(),
        network: FakeTaskCommentRepository = FakeTaskCommentRepository(),
        currentUser: User? = User(id: 9, username: "me"),
    ) async throws -> Fixture {
        let directory = temporaryDirectory()
        let store = try LocalStore(directory: directory)
        let engine = SyncEngine(
            localStore: store,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: network,
            accountID: accountID,
        )
        let repository = OfflineTaskCommentRepository(
            localStore: store,
            accountID: accountID,
            syncRequester: TestSyncRequester(
                engine: engine,
                reachability: FakeCommentReachabilityMonitor(isReachable: online),
            ),
            currentUser: currentUser,
        )
        let projectRow = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        try await store.write { db in try projectRow.insert(db) }
        return Fixture(
            repository: repository, store: store, storeDirectory: directory, network: network,
            projectLocalID: projectRow.localID, accountID: accountID, engine: engine,
        )
    }

    @discardableResult
    private func seedTask(
        in fixture: Fixture, remoteID: Int?, title: String = "Buy milk",
    ) async throws -> TaskRecord {
        let row = TaskRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: remoteID, title: title, description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: fixture.projectLocalID, serverUpdatedAt: nil,
        )
        try await fixture.store.write { db in try row.insert(db) }
        return row
    }

    @discardableResult
    private func seedComment(
        in fixture: Fixture, taskLocalID: UUID, remoteID: Int?, text: String = "Looks good",
        created: Date = Date(timeIntervalSince1970: 1_700_000_000), localID: UUID = UUID(),
    ) async throws -> TaskCommentRecord {
        let row = TaskCommentRecord(
            localID: localID, accountID: fixture.accountID, remoteID: remoteID, taskLocalID: taskLocalID,
            comment: text, authorID: 1, authorUsername: "me", authorName: "Me", authorEmail: nil,
            created: created, updated: created,
        )
        try await fixture.store.write { db in try row.insert(db) }
        return row
    }

    @Test(arguments: [false, true])
    func `same second comments keep their order through an edit retry refresh and reopening`(
        online: Bool,
    ) async throws {
        let fixture = try await makeRepository(online: online)
        let task = try await seedTask(in: fixture, remoteID: 5)
        let second = 1_794_191_456.0
        let author = User(id: 1, username: "me")
        // Use UUIDs opposite to the server IDs so an equal-date UUID fallback
        // cannot accidentally pass after a complete thread refresh.
        try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: 47, text: "A",
            created: Date(timeIntervalSince1970: second + 0.771),
            localID: #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")),
        )
        try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: 48, text: "B",
            created: Date(timeIntervalSince1970: second + 0.968),
            localID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        )
        fixture.network.comments = [
            TaskComment(
                id: 47,
                comment: "A",
                author: author,
                created: Date(timeIntervalSince1970: second),
                updated: Date(timeIntervalSince1970: second),
            ),
            TaskComment(
                id: 48,
                comment: "B",
                author: author,
                created: Date(timeIntervalSince1970: second),
                updated: Date(timeIntervalSince1970: second),
            ),
        ]
        let expected: [EntityID] = [.remote(47), .remote(48)]
        #expect(try await fixture.repository.fetchComments(taskID: 5).map(\.id) == expected)
        fixture.network.updateError = .timeout
        _ = try await fixture.repository.updateComment(48, text: "B edited", onTask: 5)
        #expect(try await fixture.repository.fetchComments(taskID: 5).map(\.id) == expected)

        try await fixture.engine.drainCommentMutations()
        #expect(try await fixture.repository.fetchComments(taskID: 5).map(\.id) == expected)
        fixture.network.updateError = nil
        try await fixture.engine.drainCommentMutations()
        let afterEdit = try await fixture.repository.fetchComments(taskID: 5)
        #expect(afterEdit.map(\.id) == expected)
        #expect(afterEdit.first { $0.id == .remote(48) }?.comment == "B edited")
        #expect(afterEdit.first { $0.id == .remote(48) }?.created == Date(timeIntervalSince1970: second))

        try await fixture.engine.pullComments(taskID: 5)
        #expect(try await fixture.repository.fetchComments(taskID: 5).map(\.id) == expected)
        let reopened = try OfflineTaskCommentRepository(
            localStore: LocalStore(directory: fixture.storeDirectory), accountID: fixture.accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await reopened.fetchComments(taskID: 5).map(\.id) == expected)
    }

    @Test
    func `creation seconds take precedence over server IDs and pending comments retain local order`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        let second = 1_794_191_456.0
        let lowUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highUUID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        // Insert out of order, with local UUIDs opposite to creation order.
        let laterPending = try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: nil, text: "Later pending",
            created: Date(timeIntervalSince1970: second + 0.9), localID: lowUUID,
        )
        try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: 1, text: "Newer second",
            created: Date(timeIntervalSince1970: second + 1),
        )
        let earlierPending = try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: nil, text: "Earlier pending",
            created: Date(timeIntervalSince1970: second + 0.1), localID: highUUID,
        )
        try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: 47, text: "Synced",
            created: Date(timeIntervalSince1970: second + 0.8),
        )
        try await seedComment(
            in: fixture, taskLocalID: task.localID, remoteID: 99, text: "Older second",
            created: Date(timeIntervalSince1970: second - 1),
        )
        let cached = try await fixture.repository.fetchComments(taskID: 5)
        #expect(cached.map(\.id) == [
            .remote(99), .remote(47), .local(earlierPending.localID), .local(laterPending.localID), .remote(1),
        ])
    }

    @Test
    func `pending comments with identical timestamps have a stable order after reopening`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: nil)
        let lowUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highUUID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: nil, localID: highUUID)
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: nil, localID: lowUUID)
        let expected: [EntityID] = [.local(lowUUID), .local(highUUID)]
        #expect(try await fixture.repository.fetchComments(taskID: .local(task.localID)).map(\.id) == expected)
        let reopened = try OfflineTaskCommentRepository(
            localStore: LocalStore(directory: fixture.storeDirectory), accountID: fixture.accountID,
            syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await reopened.fetchComments(taskID: .local(task.localID)).map(\.id) == expected)
    }

    @Test
    func `failure saving coverage rolls back downloaded comments too`() async throws {
        let fixture = try await makeRepository(online: false)
        _ = try await seedTask(in: fixture, remoteID: 5)
        fixture.network.comments = [TaskComment(
            id: 21, comment: "Remote", author: User(id: 1, username: "me"), created: Date(), updated: Date(),
        )]
        try await fixture.store.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_comment_coverage BEFORE INSERT ON taskCommentSync
            BEGIN SELECT RAISE(ABORT, 'Simulated disk failure'); END;
            """)
        }
        await #expect(throws: (any Error).self) { try await fixture.engine.pullComments(taskID: .remote(5)) }
        let snapshot = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(snapshot.comments.isEmpty)
        #expect(snapshot.lastSuccessfulDownloadAt == nil)
    }

    @Test
    func `local task coverage changes when the task is assigned a server identity`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: nil)
        let local = try await fixture.repository.fetchCommentSnapshot(taskID: .local(task.localID))
        #expect(local.isLocalOnly)
        #expect(local.lastSuccessfulDownloadAt == nil)
        try await fixture.store.write { db in
            var synced = task
            synced.remoteID = 5
            try synced.update(db)
        }
        let synced = try await fixture.repository.fetchCommentSnapshot(taskID: .local(task.localID))
        #expect(!synced.isLocalOnly)
        #expect(synced.lastSuccessfulDownloadAt == nil)
    }

    @Test
    func `empty conversations are unknown until a successful download and remain known after reopening`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        let unknown = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(unknown.comments.isEmpty)
        #expect(unknown.lastSuccessfulDownloadAt == nil)
        #expect(fixture.network.fetchedTaskIDs.isEmpty)

        try await fixture.engine.pullComments(taskID: .local(task.localID))
        let downloaded = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(downloaded.comments.isEmpty)
        #expect(downloaded.lastSuccessfulDownloadAt != nil)

        let reopenedStore = try LocalStore(directory: fixture.storeDirectory)
        let reopened = OfflineTaskCommentRepository(
            localStore: reopenedStore, accountID: fixture.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        let persisted = try await reopened.fetchCommentSnapshot(taskID: .remote(5))
        #expect(persisted.lastSuccessfulDownloadAt == downloaded.lastSuccessfulDownloadAt)
    }

    @Test
    func `failed and cancelled downloads do not establish or erase coverage`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        fixture.network.fetchError = .timeout
        await #expect(throws: VikunjaError.timeout) {
            try await fixture.engine.pullComments(taskID: .local(task.localID))
        }
        #expect(try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5)).lastSuccessfulDownloadAt == nil)
        fixture.network.fetchError = nil
        try await fixture.engine.pullComments(taskID: .remote(5))
        let original = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        let originalDate = original.lastSuccessfulDownloadAt
        fixture.network.fetchError = .timeout
        await #expect(throws: VikunjaError.timeout) { try await fixture.engine.pullComments(taskID: .remote(5)) }
        let afterFailure = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(afterFailure.lastSuccessfulDownloadAt == originalDate)
        fixture.network.fetchError = nil
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await fixture.engine.pullComments(taskID: .remote(5))
        }
        await #expect(throws: (any Error).self) { try await cancelled.value }
        let afterCancellation = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(afterCancellation.lastSuccessfulDownloadAt == originalDate)
    }

    @Test
    func `legacy and offline created comments do not imply complete coverage`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 21)
        _ = try await fixture.repository.addComment("Pending", toTask: .remote(5))
        let snapshot = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(snapshot.comments.count == 2)
        #expect(snapshot.lastSuccessfulDownloadAt == nil)
        try await fixture.engine.pullComments(taskID: .remote(5))
        let refreshed = try await fixture.repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(refreshed.comments.map(\.comment) == ["Pending"])
        #expect(refreshed.lastSuccessfulDownloadAt != nil)
    }

    @Test
    func `coverage belongs to one task and account and cascades on deletion`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        _ = try await seedTask(in: fixture, remoteID: 6)
        try await fixture.engine.pullComments(taskID: .remote(5))
        #expect(try await fixture.repository.fetchCommentSnapshot(taskID: .remote(6)).lastSuccessfulDownloadAt == nil)
        let other = OfflineTaskCommentRepository(
            localStore: fixture.store, accountID: UUID(), syncRequester: NoopKanbanSyncRequester(),
        )
        await #expect(throws: VikunjaError.notFound) { try await other.fetchCommentSnapshot(taskID: .remote(5)) }
        try await fixture.store.write { db in try task.delete(db) }
        let remaining = try await fixture.store.read { db in try TaskCommentSyncRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `an explicit comment pull populates the local query`() async throws {
        let network = FakeTaskCommentRepository()
        network.comments = [
            TaskComment(
                id: .remote(21), comment: "Server comment", author: User(id: 1, username: "me"),
                created: Date(timeIntervalSince1970: 1_700_000_000),
                updated: Date(timeIntervalSince1970: 1_700_000_000),
            ),
        ]
        let fixture = try await makeRepository(online: true, network: network)
        let task = try await seedTask(in: fixture, remoteID: 5)

        #expect(try await fixture.repository.fetchComments(taskID: .local(task.localID)).isEmpty)
        #expect(network.fetchedTaskIDs.isEmpty)
        try await fixture.engine.pullComments(taskID: .local(task.localID))
        let comments = try await fixture.repository.fetchComments(taskID: .local(task.localID))

        #expect(comments.map(\.comment) == ["Server comment"])
        #expect(comments.map(\.id) == [.remote(21)])
        #expect(network.fetchedTaskIDs == [.remote(5)])
        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [21])
    }

    @Test
    func `fetch while offline returns the cache without touching the network`() async throws {
        let network = FakeTaskCommentRepository()
        let fixture = try await makeRepository(online: false, network: network)
        let task = try await seedTask(in: fixture, remoteID: 5)
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 21)

        let comments = try await fixture.repository.fetchComments(taskID: .local(task.localID))

        #expect(comments.map(\.id) == [.remote(21)])
        #expect(network.fetchedTaskIDs.isEmpty)
    }

    @Test
    func `add while offline inserts locally with the cached user and queues a create`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)

        let created = try await fixture.repository.addComment("Looks good", toTask: .local(task.localID))

        #expect(localID(of: created.id) != nil)
        #expect(created.author.username == "me")
        #expect(!created.isEdited)
        #expect(fixture.network.addedComments.isEmpty)
        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.count == 1)
        #expect(rows[0].remoteID == nil)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].entityType == .comment)
        #expect(queued[0].operation == .create)
        #expect(queued[0].targetLocalID == localID(of: created.id))
    }

    @Test
    func `add while online drains immediately and patches the local row with the server id`() async throws {
        let fixture = try await makeRepository(online: true)
        _ = try await seedTask(in: fixture, remoteID: 5)

        let created = try await fixture.repository.addComment("Looks good", toTask: .remote(5))

        #expect(created.id == .remote(1))
        #expect(fixture.network.addedComments.map(\.taskID) == [.remote(5)])
        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [1])
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `add against a task that has not synced yet leaves the create queued`() async throws {
        let fixture = try await makeRepository(online: true)
        let task = try await seedTask(in: fixture, remoteID: nil)

        let created = try await fixture.repository.addComment("Looks good", toTask: .local(task.localID))

        #expect(fixture.network.addedComments.isEmpty)
        #expect(localID(of: created.id) != nil)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(queued[0].status == .pending)
    }

    @Test
    func `editing a not-yet-synced comment coalesces into its pending create`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        let created = try await fixture.repository.addComment("First", toTask: .local(task.localID))

        let updated = try await fixture.repository.updateComment(
            created.id, text: "Second", onTask: .local(task.localID),
        )

        #expect(updated.comment == "Second")
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        let payload = try JSONDecoder().decode(
            TaskCommentCreatePayload.self, from: Data((queued[0].payload ?? "").utf8),
        )
        #expect(payload.text == "Second")
    }

    @Test
    func `offline edit preserves the edited indicator when reloading cached comments`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 21)

        let updated = try await fixture.repository.updateComment(
            .remote(21), text: "Edited offline", onTask: .local(task.localID),
        )
        let cached = try await fixture.repository.fetchComments(taskID: .local(task.localID))

        #expect(updated.isEdited)
        #expect(cached.count == 1)
        #expect(cached.first?.isEdited == true)
        #expect(fixture.network.updatedComments.isEmpty)
    }

    @Test
    func `editing a synced comment while online drains the update`() async throws {
        let network = FakeTaskCommentRepository()
        network.comments = [
            TaskComment(
                id: .remote(21), comment: "First", author: User(id: 1, username: "me"),
                created: Date(timeIntervalSince1970: 1_700_000_000),
                updated: Date(timeIntervalSince1970: 1_700_000_000),
            ),
        ]
        let fixture = try await makeRepository(online: true, network: network)
        let task = try await seedTask(in: fixture, remoteID: 5)
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 21, text: "First")

        let updated = try await fixture.repository.updateComment(
            .remote(21), text: "Second", onTask: .local(task.localID),
        )

        #expect(updated.comment == "Second")
        #expect(network.updatedComments.map(\.commentID) == [.remote(21)])
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `deleting a not-yet-synced comment removes it without queueing a delete`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        let created = try await fixture.repository.addComment("First", toTask: .local(task.localID))

        try await fixture.repository.deleteComment(created.id, fromTask: .local(task.localID))

        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `deleting a synced comment while offline removes it locally and queues the delete`() async throws {
        let fixture = try await makeRepository(online: false)
        let task = try await seedTask(in: fixture, remoteID: 5)
        try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 21)

        try await fixture.repository.deleteComment(.remote(21), fromTask: .local(task.localID))

        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .delete)
        let payload = try JSONDecoder().decode(
            TaskCommentDeletePayload.self, from: Data((queued[0].payload ?? "").utf8),
        )
        #expect(payload.remoteID == 21)
    }

    @Test
    func `pulling keeps a locally edited comment and does not resurrect a pending delete`() async throws {
        let network = FakeTaskCommentRepository()
        network.comments = [
            TaskComment(
                id: .remote(21), comment: "Server old", author: User(id: 1, username: "me"),
                created: Date(timeIntervalSince1970: 1_700_000_000),
                updated: Date(timeIntervalSince1970: 1_700_000_000),
            ),
            TaskComment(
                id: .remote(22), comment: "Brand new", author: User(id: 1, username: "me"),
                created: Date(timeIntervalSince1970: 1_700_000_100),
                updated: Date(timeIntervalSince1970: 1_700_000_100),
            ),
            TaskComment(
                id: .remote(23), comment: "Deleted", author: User(id: 1, username: "me"),
                created: Date(timeIntervalSince1970: 1_700_000_200),
                updated: Date(timeIntervalSince1970: 1_700_000_200),
            ),
        ]
        let fixture = try await makeRepository(online: true, network: network)
        let task = try await seedTask(in: fixture, remoteID: 5)
        let edited = try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 21, text: "Local edit")
        let deleted = try await seedComment(in: fixture, taskLocalID: task.localID, remoteID: 23, text: "Deleted")

        try await fixture.store.write { db in
            var editItem = try MutationQueueRecord(
                id: nil, accountID: fixture.accountID, entityType: .comment, operation: .update,
                targetLocalID: edited.localID,
                payload: String(
                    bytes: JSONEncoder().encode(
                        TaskCommentUpdatePayload(taskLocalID: task.localID, text: "Local edit"),
                    ),
                    encoding: .utf8,
                ) ?? "",
                createdAt: Date(), retryCount: 0, lastError: nil, status: .pending,
                needsConflictResolution: false,
            )
            try editItem.insert(db)
            var deleteItem = try MutationQueueRecord(
                id: nil, accountID: fixture.accountID, entityType: .comment, operation: .delete,
                targetLocalID: deleted.localID,
                payload: String(
                    bytes: JSONEncoder().encode(
                        TaskCommentDeletePayload(taskLocalID: task.localID, remoteID: 23),
                    ),
                    encoding: .utf8,
                ) ?? "",
                createdAt: Date(), retryCount: 0, lastError: nil, status: .pending,
                needsConflictResolution: false,
            )
            try deleteItem.insert(db)
            try deleted.delete(db)
        }

        try await fixture.engine.pullComments(taskID: .local(task.localID))
        let comments = try await fixture.repository.fetchComments(taskID: .local(task.localID))

        #expect(comments.map(\.id) == [.remote(21), .remote(22)])
        #expect(comments.first { $0.id == .remote(21) }?.comment == "Local edit")
        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.compactMap(\.remoteID).sorted() == [21, 22])
    }
}
