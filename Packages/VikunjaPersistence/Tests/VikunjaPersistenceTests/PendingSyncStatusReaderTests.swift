import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct PendingSyncStatusReaderTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(directory: temporaryDirectory())
    }

    private func projectRecord(
        localID: UUID,
        accountID: UUID,
        remoteID: Int?,
    ) -> ProjectRecord {
        ProjectRecord(
            localID: localID,
            accountID: accountID,
            remoteID: remoteID,
            title: "Project",
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
        remoteID: Int?,
    ) -> TaskRecord {
        TaskRecord(
            localID: localID,
            accountID: accountID,
            remoteID: remoteID,
            title: "Task",
            description: nil,
            isDone: false,
            dueDate: nil,
            priority: 0,
            projectLocalID: UUID(),
            serverUpdatedAt: nil,
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

    /// Inserts the row and its queued mutation in one transaction, so an
    /// observation sees a single atomic change rather than an intermediate
    /// "row exists but nothing is queued" snapshot.
    private func insertPendingProject(
        _ record: ProjectRecord,
        mutation item: MutationQueueRecord,
        in store: LocalStore,
    ) async throws {
        try await store.write { db in
            try record.insert(db)
            var item = item
            try item.insert(db)
        }
    }

    private func insertPendingTask(
        _ record: TaskRecord,
        mutation item: MutationQueueRecord,
        in store: LocalStore,
    ) async throws {
        try await store.write { db in
            // `task.projectLocalID` is a foreign key, so the owning project
            // has to exist even though these tests only assert on the task's
            // own status.
            try projectRecord(
                localID: record.projectLocalID, accountID: record.accountID, remoteID: nil,
            ).insert(db)
            try record.insert(db)
            var item = item
            try item.insert(db)
        }
    }

    @Test
    func `an empty queue yields no statuses`() async throws {
        let store = try makeStore()
        let accountID = UUID()

        #expect(try await store.pendingSyncStatuses(accountID: accountID).isEmpty)
    }

    @Test
    func `a project created offline is keyed by its local id`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await insertPendingProject(
            projectRecord(localID: localID, accountID: accountID, remoteID: nil),
            mutation: mutation(
                entityType: .project, operation: .create, targetLocalID: localID, accountID: accountID,
            ),
            in: store,
        )

        let statuses = try await store.pendingSyncStatuses(accountID: accountID)

        #expect(statuses == [SyncItemKey(kind: .project, id: .local(localID)): .pending])
    }

    @Test
    func `a project that already has a remote id is keyed by both ids`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await insertPendingProject(
            projectRecord(localID: localID, accountID: accountID, remoteID: 42),
            mutation: mutation(
                entityType: .project, operation: .update, targetLocalID: localID, accountID: accountID,
            ),
            in: store,
        )

        let statuses = try await store.pendingSyncStatuses(accountID: accountID)

        #expect(statuses[SyncItemKey(kind: .project, id: .local(localID))] == .pending)
        #expect(statuses[SyncItemKey(kind: .project, id: .remote(42))] == .pending)
    }

    @Test
    func `a task and a project sharing a remote id get separate statuses`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let projectLocalID = UUID()
        let taskLocalID = UUID()

        try await insertPendingProject(
            projectRecord(localID: projectLocalID, accountID: accountID, remoteID: 7),
            mutation: mutation(
                entityType: .project, operation: .update, targetLocalID: projectLocalID, accountID: accountID,
            ),
            in: store,
        )
        try await insertPendingTask(
            taskRecord(localID: taskLocalID, accountID: accountID, remoteID: 7),
            mutation: mutation(
                entityType: .task, operation: .update, targetLocalID: taskLocalID, accountID: accountID,
            ),
            in: store,
        )

        let statuses = try await store.pendingSyncStatuses(accountID: accountID)

        #expect(statuses[SyncItemKey(kind: .project, id: .remote(7))] == .pending)
        #expect(statuses[SyncItemKey(kind: .task, id: .remote(7))] == .pending)
    }

    @Test
    func `a task label mutation is reported against the task`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let taskLocalID = UUID()

        try await insertPendingTask(
            taskRecord(localID: taskLocalID, accountID: accountID, remoteID: 9),
            mutation: mutation(
                entityType: .task, operation: .addLabel, targetLocalID: taskLocalID, accountID: accountID,
            ),
            in: store,
        )

        let statuses = try await store.pendingSyncStatuses(accountID: accountID)

        #expect(statuses[SyncItemKey(kind: .task, id: .remote(9))] == .pending)
    }

    @Test
    func `a failed mutation in the chain outranks a pending one`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await store.write { db in
            try projectRecord(localID: localID, accountID: accountID, remoteID: nil).insert(db)
            var pending = mutation(
                entityType: .project, operation: .create, targetLocalID: localID, accountID: accountID,
            )
            try pending.insert(db)
            var failed = mutation(
                entityType: .project, operation: .update, targetLocalID: localID, accountID: accountID,
                status: .failed,
            )
            failed.createdAt = Date().addingTimeInterval(1)
            try failed.insert(db)
        }

        let statuses = try await store.pendingSyncStatuses(accountID: accountID)

        #expect(statuses[SyncItemKey(kind: .project, id: .local(localID))] == .failed)
    }

    @Test
    func `an unresolved conflict surfaces as failed`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await insertPendingProject(
            projectRecord(localID: localID, accountID: accountID, remoteID: 3),
            mutation: mutation(
                entityType: .project, operation: .update, targetLocalID: localID, accountID: accountID,
                needsConflictResolution: true,
            ),
            in: store,
        )

        let statuses = try await store.pendingSyncStatuses(accountID: accountID)

        #expect(statuses[SyncItemKey(kind: .project, id: .remote(3))] == .failed)
    }

    @Test
    func `another account's queue is ignored`() async throws {
        let store = try makeStore()
        let activeAccountID = UUID()
        let otherAccountID = UUID()
        let localID = UUID()

        try await insertPendingProject(
            projectRecord(localID: localID, accountID: otherAccountID, remoteID: nil),
            mutation: mutation(
                entityType: .project, operation: .create, targetLocalID: localID, accountID: otherAccountID,
            ),
            in: store,
        )

        #expect(try await store.pendingSyncStatuses(accountID: activeAccountID).isEmpty)
    }

    @Test
    func `label and comment mutations have no row indicator`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await store.write { db in
            var label = mutation(
                entityType: .label, operation: .create, targetLocalID: localID, accountID: accountID,
            )
            try label.insert(db)
            var comment = mutation(
                entityType: .comment, operation: .create, targetLocalID: localID, accountID: accountID,
            )
            try comment.insert(db)
        }

        #expect(try await store.pendingSyncStatuses(accountID: accountID).isEmpty)
    }

    @Test
    func `a mutation whose row no longer exists is skipped`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        try await store.write { db in
            var item = mutation(
                entityType: .project, operation: .delete, targetLocalID: localID, accountID: accountID,
            )
            try item.insert(db)
        }

        #expect(try await store.pendingSyncStatuses(accountID: accountID).isEmpty)
    }

    @Test
    func `observation emits a fresh snapshot after an edit is queued`() async throws {
        let store = try makeStore()
        let accountID = UUID()
        let localID = UUID()

        let updates = await store.observePendingSyncStatuses(accountID: accountID)
        var iterator = updates.makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial?.isEmpty == true)

        try await insertPendingProject(
            projectRecord(localID: localID, accountID: accountID, remoteID: nil),
            mutation: mutation(
                entityType: .project, operation: .create, targetLocalID: localID, accountID: accountID,
            ),
            in: store,
        )

        let update = try #require(try await iterator.next())
        #expect(update[SyncItemKey(kind: .project, id: .local(localID))] == .pending)
    }
}
