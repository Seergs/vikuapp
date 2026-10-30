import Foundation

/// Streams one account's queued mutations for the Settings "Pending Sync"
/// screen. The stream emits an initial snapshot and then again whenever the
/// queue or a target row changes, so the screen follows a drain without
/// polling.
public protocol PendingSyncOperationsProviding: Sendable {
    func observePendingSyncOperations(
        accountID: UUID,
    ) async -> AsyncThrowingStream<[PendingSyncOperation], Error>

    #if DEBUG
    /// Developer recovery tool: drops only queue entries for this account.
    /// Leaves cached entities untouched and does not cancel requests already in flight.
    func clearPendingSyncQueue(accountID: UUID) async throws
    #endif

    /// Removes `id` from the account's queue only when it's a conflict.
    /// Conflicted items are never drained, so this only drops the abandoned
    /// local attempt instead of changing either side. A conflict normally
    /// triggers a server pull, but a failed pull can leave the local row
    /// stale until the next successful sync.
    func discardConflictedPendingSyncOperation(id: Int64, accountID: UUID) async throws
}
