import Foundation
import GRDB
import VikunjaCore

/// Reads the account's mutation queue as display-ready rows for the Settings
/// "Pending Sync" screen. Kept separate from `LocalStore` so the query stays
/// unit-testable without an observation running, and so the GRDB schema
/// types never leak into `VikunjaCore`.
enum PendingSyncOperationsReader {
    /// Every queued mutation for `accountID`, oldest first. Unlike
    /// `PendingSyncStatusReader`, this doesn't skip rows whose target is
    /// missing: a queued delete is still worth showing even if its local row
    /// is already gone. In that case `targetTitle` is `nil`.
    static func operations(accountID: UUID, db: Database) throws -> [PendingSyncOperation] {
        try MutationQueueRecord.fetchAll(db)
            .filter { $0.accountID == accountID }
            .compactMap { item in
                guard let id = item.id else { return nil }
                return try PendingSyncOperation(
                    id: id,
                    entity: item.entityType.pendingSyncEntity,
                    action: item.operation.pendingSyncAction,
                    targetTitle: title(for: item, db: db),
                    createdAt: item.createdAt,
                    status: item.status == .failed || item.needsConflictResolution ? .failed : .pending,
                    needsConflictResolution: item.needsConflictResolution,
                    failureMessage: item.lastError.flatMap(KanbanCreationFailure.init(rawValue:))?.message,
                )
            }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id < $1.id
                    : $0.createdAt < $1.createdAt
            }
    }

    private static func title(for item: MutationQueueRecord, db: Database) throws -> String? {
        switch item.entityType {
        case .project, .filter:
            try ProjectRecord.fetchOne(db, key: item.targetLocalID)?.title
        case .label:
            try LabelRecord.fetchOne(db, key: item.targetLocalID)?.title
        case .task:
            try TaskRecord.fetchOne(db, key: item.targetLocalID)?.title
        case .comment:
            try commentTitle(localID: item.targetLocalID, db: db)
        }
    }

    /// A comment's most useful label is the task it belongs to, not the
    /// comment body itself.
    private static func commentTitle(localID: UUID, db: Database) throws -> String? {
        guard let comment = try TaskCommentRecord.fetchOne(db, key: localID) else { return nil }
        return try TaskRecord.fetchOne(db, key: comment.taskLocalID)?.title
    }
}

private extension MutationEntityType {
    var pendingSyncEntity: PendingSyncEntity {
        switch self {
        case .project: .project
        case .filter: .filter
        case .label: .label
        case .task: .task
        case .comment: .comment
        }
    }
}

private extension MutationOperation {
    var pendingSyncAction: PendingSyncAction {
        switch self {
        case .create: .create
        case .update: .update
        case .delete: .delete
        case .addLabel: .addLabel
        case .removeLabel: .removeLabel
        case .addRelation: .addRelation
        case .removeRelation: .removeRelation
        }
    }
}
