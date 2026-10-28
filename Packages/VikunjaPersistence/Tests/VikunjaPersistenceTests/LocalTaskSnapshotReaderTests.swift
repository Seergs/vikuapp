import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct LocalTaskSnapshotReaderTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func seedProject(
        in store: LocalStore,
        accountID: UUID,
        localID: UUID = UUID(),
        remoteID: Int?,
        title: String = "Work",
        hexColor: String = "#196AFF",
    ) async throws -> ProjectRecord {
        let row = ProjectRecord(
            localID: localID,
            accountID: accountID,
            remoteID: remoteID,
            title: title,
            description: nil,
            isArchived: false,
            isFavorite: false,
            parentProjectLocalID: nil,
            position: 0,
            hexColor: hexColor,
            serverUpdatedAt: nil,
        )
        try await store.write { db in try row.insert(db) }
        return row
    }

    private func seedTask(
        in store: LocalStore,
        accountID: UUID,
        projectLocalID: UUID,
        localID: UUID = UUID(),
        remoteID: Int?,
        title: String = "Task",
        isDone: Bool = false,
        dueDate: Date? = nil,
        priority: Int = 0,
    ) async throws -> TaskRecord {
        let row = TaskRecord(
            localID: localID,
            accountID: accountID,
            remoteID: remoteID,
            title: title,
            description: nil,
            isDone: isDone,
            dueDate: dueDate,
            priority: priority,
            projectLocalID: projectLocalID,
            serverUpdatedAt: nil,
        )
        try await store.write { db in try row.insert(db) }
        return row
    }

    private func seedPendingDelete(
        in store: LocalStore,
        accountID: UUID,
        taskLocalID: UUID,
    ) async throws {
        try await store.write { db in
            var row = MutationQueueRecord(
                id: nil,
                accountID: accountID,
                entityType: .task,
                operation: .delete,
                targetLocalID: taskLocalID,
                payload: nil,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try row.insert(db)
        }
    }

    @Test
    func `reads remote tasks and projects while hiding local-only and pending-delete rows`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountID = UUID()
        let project = try await seedProject(in: store, accountID: accountID, remoteID: 1)
        _ = try await seedProject(in: store, accountID: accountID, remoteID: nil, title: "Local project")
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await seedTask(
            in: store, accountID: accountID, projectLocalID: project.localID,
            remoteID: 10, title: "Synced", isDone: true, dueDate: dueDate, priority: 3,
        )
        _ = try await seedTask(
            in: store, accountID: accountID, projectLocalID: project.localID,
            remoteID: nil, title: "Local only",
        )
        let deleted = try await seedTask(
            in: store, accountID: accountID, projectLocalID: project.localID,
            remoteID: 12, title: "Deleted",
        )
        try await seedPendingDelete(in: store, accountID: accountID, taskLocalID: deleted.localID)
        let lastPulledAt = Date(timeIntervalSince1970: 1_700_000_100)
        try await store.write { db in
            try SyncStateRecord(accountID: accountID, entityType: .task, lastPulledAt: lastPulledAt).insert(db)
        }

        let snapshot = try await LocalTaskSnapshotReader(localStore: store).loadSnapshot(accountID: accountID)

        let unwrapped = try #require(snapshot)
        #expect(unwrapped.tasks.map(\.id) == [.remote(10)])
        #expect(unwrapped.tasks.first?.title == "Synced")
        #expect(unwrapped.tasks.first?.isDone == true)
        #expect(unwrapped.tasks.first?.dueDate == dueDate)
        #expect(unwrapped.tasks.first?.priority == .high)
        #expect(unwrapped.projects.map(\.id) == [.remote(1)])
        #expect(unwrapped.projects.first?.hexColor == "#196AFF")
        #expect(unwrapped.lastPulledAt == lastPulledAt)
    }

    @Test
    func `resolves the only stored account when no account id is available`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountID = UUID()
        let project = try await seedProject(in: store, accountID: accountID, remoteID: 1)
        _ = try await seedTask(
            in: store, accountID: accountID, projectLocalID: project.localID, remoteID: 10,
        )

        let snapshot = try await LocalTaskSnapshotReader(localStore: store).loadSnapshot(accountID: nil)

        #expect(try #require(snapshot).tasks.map(\.id) == [.remote(10)])
    }

    @Test
    func `returns nothing when several accounts are stored and no account id is available`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        for remoteID in [1, 2] {
            let accountID = UUID()
            let project = try await seedProject(in: store, accountID: accountID, remoteID: remoteID)
            _ = try await seedTask(
                in: store, accountID: accountID, projectLocalID: project.localID, remoteID: remoteID * 10,
            )
        }

        let snapshot = try await LocalTaskSnapshotReader(localStore: store).loadSnapshot(accountID: nil)

        #expect(snapshot == nil)
    }

    @Test
    func `returns nothing for an empty store`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())

        let snapshot = try await LocalTaskSnapshotReader(localStore: store).loadSnapshot(accountID: UUID())

        #expect(snapshot == nil)
    }
}
