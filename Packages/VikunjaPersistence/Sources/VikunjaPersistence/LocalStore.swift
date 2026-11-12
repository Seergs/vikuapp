import Foundation
import GRDB
import VikunjaCore

public enum LocalStoreError: Error, Sendable, LocalizedError {
    /// The App Group container isn't available - the App Groups entitlement
    /// is missing, or the identifier doesn't match between targets.
    case containerUnavailable
    case accountReloadInProgress

    public var errorDescription: String? {
        switch self {
        case .containerUnavailable: nil
        case .accountReloadInProgress:
            String(localized: "This account is being reloaded. Try again when it finishes.", bundle: .module)
        }
    }
}

/// Actor wrapping a GRDB `DatabasePool` (WAL mode, GRDB's default for that
/// type) around the offline-sync schema. All reads and writes to the local
/// SQLite database go through this actor, mirroring `URLSessionAPIClient`
/// being an actor rather than a class with locks.
public actor LocalStore {
    private let dbPool: DatabasePool
    nonisolated let executionLifecycle: DatabaseExecutionLifecycle?
    private var reloadingAccounts: Set<UUID> = []

    /// - Parameter directory: where the database file lives, created if
    ///   missing. Pass the App Group container so a widget extension can
    ///   eventually read the same database; a scratch directory works for
    ///   tests.
    public init(directory: URL, executionLifecycle: DatabaseExecutionLifecycle? = nil) throws {
        try executionLifecycle?.checkAccess()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.observesSuspensionNotifications = executionLifecycle != nil
        let dbPool = try DatabasePool(
            path: directory.appendingPathComponent("viku.sqlite").path, configuration: configuration,
        )
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(on: &migrator)
        try migrator.migrate(dbPool)
        self.dbPool = dbPool
        self.executionLifecycle = executionLifecycle
    }

    public init(appGroupIdentifier: String, executionLifecycle: DatabaseExecutionLifecycle? = nil) throws {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        )
        guard let directory else {
            throw LocalStoreError.containerUnavailable
        }
        try self.init(directory: directory, executionLifecycle: executionLifecycle)
    }

    public func read<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        let generation = executionLifecycle?.suspensionGeneration
        do {
            return try await dbPool.read(value)
        } catch { throw normalizedInterruption(error, since: generation) }
    }

    public func write<T: Sendable>(_ updates: @Sendable (Database) throws -> T) async throws -> T {
        try await writeTransaction(checkReloads: true, updates)
    }

    private func writeTransaction<T: Sendable>(
        checkReloads: Bool, _ updates: @Sendable (Database) throws -> T,
    ) async throws -> T {
        // Only the rare account reload pays for the snapshot guard. Its own
        // atomic replacement bypasses that guard, but still respects suspension.
        let lockedAccounts = checkReloads ? reloadingAccounts : []
        try executionLifecycle?.checkAccess()
        let generation = executionLifecycle?.suspensionGeneration
        do {
            return try await dbPool.write { db in
                try Task.checkCancellation()
                try self.executionLifecycle?.checkAccess()
                let before = try lockedAccounts.map { try AccountSnapshot(accountID: $0, db: db) }
                let result = try updates(db)
                let after = try lockedAccounts.map { try AccountSnapshot(accountID: $0, db: db) }
                guard before == after else { throw LocalStoreError.accountReloadInProgress }
                try Task.checkCancellation()
                try self.executionLifecycle?.checkAccess()
                guard self.executionLifecycle?.suspensionGeneration == generation else {
                    throw CancellationError()
                }
                return result
            }
        } catch { throw normalizedInterruption(error, since: generation) }
    }

    private nonisolated func normalizedInterruption(_ error: any Error, since generation: Int?) -> any Error {
        if Task.isCancelled {
            return CancellationError()
        }
        if let lifecycle = executionLifecycle,
           lifecycle.isSuspended || lifecycle.suspensionGeneration != generation,
           let databaseError = error as? DatabaseError,
           databaseError.resultCode == .SQLITE_INTERRUPT || databaseError.resultCode == .SQLITE_ABORT {
            return CancellationError()
        }
        return error
    }

    /// The writer barrier lets previously submitted writes settle before the snapshot.
    func beginAccountReload(accountID: UUID) async throws -> AccountSnapshot {
        guard reloadingAccounts.insert(accountID).inserted else { throw LocalStoreError.accountReloadInProgress }
        do {
            return try await write { db in try AccountSnapshot(accountID: accountID, db: db) }
        } catch {
            reloadingAccounts.remove(accountID)
            throw error
        }
    }

    func endAccountReload(accountID: UUID) {
        reloadingAccounts.remove(accountID)
    }

    func replaceAccount(accountID: UUID, with snapshot: AccountSnapshot) async throws {
        try await writeTransaction(checkReloads: false) { db in
            try Task.checkCancellation()
            try snapshot.replace(accountID: accountID, db: db)
            try Task.checkCancellation()
        }
    }

    /// Observe account content, including queued optimistic edits. Comparing
    /// account snapshots suppresses writes belonging only to another account.
    public func observeChanges(accountID: UUID) -> AsyncThrowingStream<Void, Error> {
        let values = ValueObservation.tracking { db in
            try AccountSnapshot(accountID: accountID, db: db, includeSyncStates: false)
        }
        .removeDuplicates()
        .values(in: dbPool)
        return recoveringObservation { continuation in
            for try await _ in values {
                continuation.yield(())
            }
        }
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
        return recoveringObservation { continuation in
            for try await statuses in values {
                continuation.yield(statuses)
            }
        }
    }

    /// The account's queued mutations as display-ready rows. One-shot read,
    /// used by tests; the Settings "Pending Sync" screen consumes the live
    /// stream below.
    public func pendingSyncOperations(accountID: UUID) async throws -> [PendingSyncOperation] {
        try await read { db in try PendingSyncOperationsReader.operations(accountID: accountID, db: db) }
    }

    /// Streams `pendingSyncOperations(accountID:)` on every change to the
    /// mutation queue or to any table a target title comes from. Backed by
    /// GRDB's `ValueObservation`, so a screen left open follows the queue as
    /// it drains. The stream ends when the consuming task is cancelled.
    public func observePendingSyncOperations(
        accountID: UUID,
    ) -> AsyncThrowingStream<[PendingSyncOperation], Error> {
        let observation = ValueObservation.tracking(
            regions: [
                Table("mutationQueueItem"),
                Table("project"),
                Table("label"),
                Table("task"),
                Table("taskComment"),
            ],
        ) { db in
            try PendingSyncOperationsReader.operations(accountID: accountID, db: db)
        }
        .removeDuplicates()
        let values = observation.values(in: dbPool)
        return recoveringObservation { continuation in
            for try await operations in values {
                continuation.yield(operations)
            }
        }
    }

    nonisolated func recoveringObservation<Value: Sendable>(
        consume: @escaping @Sendable (AsyncThrowingStream<Value, Error>.Continuation) async throws -> Void,
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let generation = self.executionLifecycle?.suspensionGeneration
                    do {
                        try await self.executionLifecycle?.waitUntilResumed()
                        try await consume(continuation)
                        continuation.finish()
                        return
                    } catch {
                        guard !Task.isCancelled else { break }
                        // A suspension can race a fast resume. Recreate the GRDB
                        // iterator even if execution has already resumed.
                        if self.normalizedInterruption(error, since: generation) is CancellationError,
                           self.executionLifecycle != nil {
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if DEBUG
    public func clearPendingSyncQueue(accountID: UUID) async throws {
        try await write { db in
            _ = try MutationQueueRecord.filter(Column("accountID") == accountID).deleteAll(db)
        }
    }
    #endif

    /// Removes one conflicted queue item. A non-conflict, another account's
    /// item, or an id that already drained is a no-op: this isn't a general
    /// cancel mechanism, only cleanup for conflicts that can never drain.
    public func discardConflictedPendingSyncOperation(id: Int64, accountID: UUID) async throws {
        try await write { db in
            guard let item = try MutationQueueRecord.fetchOne(db, key: id),
                  item.accountID == accountID,
                  item.canDiscardConflict
            else { return }
            try item.delete(db)
        }
    }
}

extension LocalStore: PendingSyncOperationsProviding {}
