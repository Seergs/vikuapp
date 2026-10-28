import Foundation
import GRDB
import VikunjaCore

public enum LocalStoreError: Error, Sendable {
    /// The App Group container isn't available - the App Groups entitlement
    /// is missing, or the identifier doesn't match between targets.
    case containerUnavailable
}

/// Actor wrapping a GRDB `DatabasePool` (WAL mode, GRDB's default for that
/// type) around the offline-sync schema. All reads and writes to the local
/// SQLite database go through this actor, mirroring `URLSessionAPIClient`
/// being an actor rather than a class with locks.
public actor LocalStore {
    private let dbPool: DatabasePool

    /// - Parameter directory: where the database file lives, created if
    ///   missing. Pass the App Group container so a widget extension can
    ///   eventually read the same database; a scratch directory works for
    ///   tests.
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPool = try DatabasePool(path: directory.appendingPathComponent("viku.sqlite").path)
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(on: &migrator)
        try migrator.migrate(dbPool)
        self.dbPool = dbPool
    }

    public init(appGroupIdentifier: String) throws {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        )
        guard let directory else {
            throw LocalStoreError.containerUnavailable
        }
        try self.init(directory: directory)
    }

    public func read<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        try await dbPool.read(value)
    }

    public func write<T: Sendable>(_ updates: @Sendable (Database) throws -> T) async throws -> T {
        try await dbPool.write(updates)
    }

    /// The current pending-sync status of every project and task with at
    /// least one queued mutation, for one account. One-shot read, used by
    /// tests and any caller that only needs a snapshot.
    public func pendingSyncStatuses(accountID: UUID) async throws -> [SyncItemKey: SyncItemStatus] {
        try await read { db in try PendingSyncStatusReader.statuses(accountID: accountID, db: db) }
    }

    /// Streams `pendingSyncStatuses(accountID:)` on every change to the
    /// mutation queue or to the project/task rows it resolves ids against.
    /// Backed by GRDB's `ValueObservation`, so the UI's row indicators appear,
    /// clear, and turn into failures without any polling. The stream ends
    /// when the consuming task is cancelled.
    public func observePendingSyncStatuses(
        accountID: UUID,
    ) -> AsyncThrowingStream<[SyncItemKey: SyncItemStatus], Error> {
        let observation = ValueObservation.tracking(
            regions: [Table("mutationQueueItem"), Table("project"), Table("task")],
        ) { db in
            try PendingSyncStatusReader.statuses(accountID: accountID, db: db)
        }
        .removeDuplicates()
        let values = observation.values(in: dbPool)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await statuses in values {
                        continuation.yield(statuses)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
