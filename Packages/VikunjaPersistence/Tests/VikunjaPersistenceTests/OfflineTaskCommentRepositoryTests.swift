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
        let network: FakeTaskCommentRepository
        let projectLocalID: UUID
        let accountID: UUID
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
        let store = try LocalStore(directory: temporaryDirectory())
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
            syncEngine: engine,
            reachability: FakeCommentReachabilityMonitor(isReachable: online),
            currentUser: currentUser,
        )
        let projectRow = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        try await store.write { db in try projectRow.insert(db) }
        return Fixture(
            repository: repository, store: store, network: network,
            projectLocalID: projectRow.localID, accountID: accountID,
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
    ) async throws -> TaskCommentRecord {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let row = TaskCommentRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: remoteID, taskLocalID: taskLocalID,
            comment: text, authorID: 1, authorUsername: "me", authorName: "Me", authorEmail: nil,
            created: now, updated: now,
        )
        try await fixture.store.write { db in try row.insert(db) }
        return row
    }

    @Test
    func `fetch while online pulls from the network and caches the result`() async throws {
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

        let comments = try await fixture.repository.fetchComments(taskID: .local(task.localID))

        #expect(comments.map(\.id) == [.remote(21), .remote(22)])
        #expect(comments.first { $0.id == .remote(21) }?.comment == "Local edit")
        let rows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(rows.compactMap(\.remoteID).sorted() == [21, 22])
    }
}
