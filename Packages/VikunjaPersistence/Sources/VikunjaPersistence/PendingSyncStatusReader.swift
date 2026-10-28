import Foundation
import GRDB
import VikunjaCore

/// Reads the per-entity sync status the UI's row indicators need out of the
/// mutation queue. Kept separate from `LocalStore` so the query itself is
/// unit-testable without an observation running, and so the GRDB schema types
/// never leak into `VikunjaCore`.
enum PendingSyncStatusReader {
    /// One entry per project or task with at least one mutation still in the
    /// queue, keyed by both its `.local` and (when it has one) `.remote` id.
    /// Keying by both matters because a row created offline is still rendered
    /// with its `.local` id even after its create has drained and the stored
    /// record has moved on to a `.remote` id; either lookup must find it.
    ///
    /// Label and comment mutations have no row-level indicator of their own.
    /// A label attached to a task is queued against the task itself and is
    /// therefore already covered by that task's entry.
    static func statuses(accountID: UUID, db: Database) throws -> [SyncItemKey: SyncItemStatus] {
        let items = try MutationQueueRecord.fetchAll(db).filter { $0.accountID == accountID }
        guard !items.isEmpty else { return [:] }

        var rowsByTarget: [Target: [MutationQueueRecord]] = [:]
        for item in items where item.entityType == .project || item.entityType == .task {
            rowsByTarget[Target(kind: item.entityType, localID: item.targetLocalID), default: []]
                .append(item)
        }

        var statuses: [SyncItemKey: SyncItemStatus] = [:]
        for (target, rows) in rowsByTarget {
            let status = aggregate(rows)
            switch target.kind {
            case .project:
                guard let row = try ProjectRecord.fetchOne(db, key: target.localID) else { continue }
                statuses[SyncItemKey(kind: .project, id: .local(row.localID))] = status
                if let remoteID = row.remoteID {
                    statuses[SyncItemKey(kind: .project, id: .remote(remoteID))] = status
                }
            case .task:
                guard let row = try TaskRecord.fetchOne(db, key: target.localID) else { continue }
                statuses[SyncItemKey(kind: .task, id: .local(row.localID))] = status
                if let remoteID = row.remoteID {
                    statuses[SyncItemKey(kind: .task, id: .remote(remoteID))] = status
                }
            case .label, .comment:
                continue
            }
        }
        return statuses
    }

    private struct Target: Hashable {
        let kind: MutationEntityType
        let localID: UUID
    }

    /// A failure (or an unresolved conflict) anywhere in the chain is what a
    /// person needs to know about, so it outranks a later row that's merely
    /// pending. `inFlight` isn't produced by `SyncEngine` today, but folding
    /// it into `pending` here keeps the indicator correct if that changes.
    private static func aggregate(_ rows: [MutationQueueRecord]) -> SyncItemStatus {
        if rows.contains(where: { $0.needsConflictResolution || $0.status == .failed }) {
            return .failed
        }
        return .pending
    }
}
