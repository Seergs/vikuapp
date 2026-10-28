import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct PendingSyncOperationsReaderTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(directory: temporaryDirectory())
    }

    private func projectRecord(
        localID: UUID,
        accountID: UUID,
        title: String = "Project",
    ) -> ProjectRecord {
        ProjectRecord(
            localID: localID,
            accountID: accountID,
            remoteID: nil,
            title: title,
            description: nil,
            isArchived: false,
            isFavorite: false,
            parentProjectLocalID: nil,
            position: 0,
            hexColor: "",
            serverUpdatedAt: nil,
        )
    }

    private func taskRecord(
        localID: UUID,
        accountID: UUID,
        projectLocalID: UUID,
        title: String = "Task",
    ) -> TaskRecord {
        TaskRecord(
            localID: localID,
            accountID: accountID,
            remoteID: nil,
            title: title,
            description: nil,
            isDone: false,
            dueDate: nil,
            priority: 0,
            projectLocalID: projectLocalID,
            serverUpdatedAt: nil,
        )
    }

    private func labelRecord(localID: UUID, accountID: UUID, title: String) -> LabelRecord {
        LabelRecord(
            localID: localID,
            accountID: accountID,
            remoteID: nil,
            title: title,
            hexColor: "",
        )
    }

    private func commentRecord(
        localID: UUID,
        accountID: UUID,
        taskLocalID: UUID,
        comment: String = "Comment",
    ) -> TaskCommentRecord {
        TaskCommentRecord(
            localID: localID,
            accountID: accountID,
            remoteID: nil,
            taskLocalID: taskLocalID,
            comment: comment,
            authorID: 1,
            authorUsername: "user",
            authorName: nil,
            authorEmail: nil,
            created: Date(),
            updated: Date(),
        )
    }

    private func mutation(
        entityType: MutationEntityType,
        operation: MutationOperation,
        targetLocalID: UUID,
        accountID: UUID,
        status: MutationStatus = .pending,
        needsConflictResolution: Bool = false,
        createdAt: Date = Date(),
    ) -> MutationQueueRecord {
        MutationQueueRecord(
            id: nil,
            accountID: accountID,
            entityType: entityType,
            operation: operation,
            targetLocalID: targetLocalID,
            payload: nil,
            createdAt: createdAt,
            retryCount: 0,
            lastError: nil,
            status: status,
            needsConflictResolution: needsConflictResolution,
        )
    }

    @Test
    func `an empty queue yields no operations`() async throws {
        let store = try makeStore()

        #expect(try await store.pendingSyncOperations(accountID: UUID()).isEmpty)
    }

    @Test
    func `discarding a conflict removes only that account's conflicted row`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let otherAccountID = UUID()
        try await store.write { db in
            var conflict = mutation(
                entityType: .project, operation: .update, targetLocalID: UUID(), accountID: accountID,
                needsConflictResolution: true,
            )
            try conflict.insert(db)
            var pending = mutation(
                entityType: .project, operation: .update, targetLocalID: UUID(), accountID: accountID,
            )
            try pending.insert(db)
            var otherAccountConflict = mutation(
                entityType: .project, operation: .update, targetLocalID: UUID(), accountID: otherAccountID,
                needsConflictResolution: true,
            )
            try otherAccountConflict.insert(db)
        }
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        let conflictID = try #require(
            queued.first { $0.accountID == accountID && $0.needsConflictResolution }?.id,
        )
        let pendingID = try #require(
            queued.first { $0.accountID == accountID && !$0.needsConflictResolution }?.id,
        )
        let otherAccountConflictID = try #require(
            queued.first { $0.accountID == otherAccountID }?.id,
        )

        try await store.discardConflictedPendingSyncOperation(id: conflictID, accountID: accountID)
        try await store.discardConflictedPendingSyncOperation(id: pendingID, accountID: accountID)
        try await store.discardConflictedPendingSyncOperation(id: otherAccountConflictID, accountID: accountID)

        let remaining = try await store.pendingSyncOperations(accountID: accountID)
        #expect(Set(remaining.map(\.id)) == [pendingID])
        #expect(try await store.pendingSyncOperations(accountID: otherAccountID).map(\.id) == [otherAccountConflictID])
    }

    @Test
    func `observation emits after a conflict is discarded`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let conflictID = try await store.write { db -> Int64? in
            var conflict = mutation(
                entityType: .project, operation: .update, targetLocalID: UUID(), accountID: accountID,
                needsConflictResolution: true,
            )
            try conflict.insert(db)
            return conflict.id
        }
        let id = try #require(conflictID)

        let updates = await store.observePendingSyncOperations(accountID: accountID)
        var iterator = updates.makeAsyncIterator()

        #expect(try await iterator.next()?.map(\.id) == [id])

        try await store.discardConflictedPendingSyncOperation(id: id, accountID: accountID)

        #expect(try await iterator.next()?.isEmpty == true)
    }

    @Test
    func `operations resolve their target titles and sort oldest first`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let projectID = UUID()
        let taskID = UUID()
        let labelID = UUID()
        let commentID = UUID()
        let now = Date()

        try await store.write { db in
            try projectRecord(localID: projectID, accountID: accountID, title: "Project Alpha").insert(db)
            try taskRecord(
                localID: taskID, accountID: accountID, projectLocalID: projectID, title: "Task Beta",
            ).insert(db)
            try labelRecord(localID: labelID, accountID: accountID, title: "Label Gamma").insert(db)
            try commentRecord(localID: commentID, accountID: accountID, taskLocalID: taskID).insert(db)

            var comment = mutation(
                entityType: .comment,
                operation: .update,
                targetLocalID: commentID,
                accountID: accountID,
                createdAt: now.addingTimeInterval(3),
            )
            try comment.insert(db)
            var task = mutation(
                entityType: .task,
                operation: .addLabel,
                targetLocalID: taskID,
                accountID: accountID,
                createdAt: now.addingTimeInterval(1),
            )
            try task.insert(db)
            var project = mutation(
                entityType: .project,
                operation: .update,
                targetLocalID: projectID,
                accountID: accountID,
                createdAt: now.addingTimeInterval(2),
            )
            try project.insert(db)
            var label = mutation(
                entityType: .label,
                operation: .create,
                targetLocalID: labelID,
                accountID: accountID,
                createdAt: now,
            )
            try label.insert(db)
        }

        let operations = try await store.pendingSyncOperations(accountID: accountID)

        #expect(operations.map(\.entity) == [.label, .task, .project, .comment])
        #expect(operations.map(\.targetTitle) == ["Label Gamma", "Task Beta", "Project Alpha", "Task Beta"])
        #expect(operations.map(\.action) == [.create, .addLabel, .update, .update])
    }

    @Test
    func `failed conflicts and in-flight mutations map to the right status`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let projectID = UUID()

        try await store.write { db in
            try projectRecord(localID: projectID, accountID: accountID).insert(db)
            var failed = mutation(
                entityType: .project, operation: .update, targetLocalID: projectID, accountID: accountID,
                status: .failed,
            )
            try failed.insert(db)
            var conflicted = mutation(
                entityType: .project, operation: .update, targetLocalID: projectID, accountID: accountID,
                needsConflictResolution: true,
            )
            try conflicted.insert(db)
            var inFlight = mutation(
                entityType: .project, operation: .update, targetLocalID: projectID, accountID: accountID,
                status: .inFlight,
            )
            try inFlight.insert(db)
        }

        let operations = try await store.pendingSyncOperations(accountID: accountID)

        #expect(operations.count == 3)
        #expect(operations.filter(\.needsConflictResolution).count == 1)
        #expect(operations.filter { $0.status == .failed }.count == 2)
        #expect(operations.filter { $0.status == .pending }.count == 1)
    }

    @Test
    func `a mutation whose target row is gone still appears without a title`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await store.write { db in
            var item = mutation(
                entityType: .project, operation: .delete, targetLocalID: localID, accountID: accountID,
            )
            try item.insert(db)
        }

        let operations = try await store.pendingSyncOperations(accountID: accountID)

        #expect(operations.count == 1)
        #expect(operations.first?.targetTitle == nil)
    }

    @Test
    func `another account's queue is ignored`() async throws {
        let store = try makeStore()
        let activeAccountID = UUID()
        let otherAccountID = UUID()
        let localID = UUID()

        try await store.write { db in
            var item = mutation(
                entityType: .project, operation: .create, targetLocalID: localID, accountID: otherAccountID,
            )
            try item.insert(db)
        }

        #expect(try await store.pendingSyncOperations(accountID: activeAccountID).isEmpty)
    }

    @Test
    func `observation emits a fresh snapshot after an edit is queued`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        let updates = await store.observePendingSyncOperations(accountID: accountID)
        var iterator = updates.makeAsyncIterator()

        #expect(try await iterator.next()?.isEmpty == true)

        try await store.write { db in
            try projectRecord(localID: localID, accountID: accountID, title: "Offline Project").insert(db)
            var item = mutation(
                entityType: .project, operation: .create, targetLocalID: localID, accountID: accountID,
            )
            try item.insert(db)
        }

        let update = try #require(try await iterator.next())
        #expect(update.count == 1)
        #expect(update.first?.targetTitle == "Offline Project")
        #expect(update.first?.status == .pending)
    }
}
