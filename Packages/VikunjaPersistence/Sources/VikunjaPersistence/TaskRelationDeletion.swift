import Foundation
import GRDB

/// Final cleanup for a locally requested deletion. Pending deletions only hide
/// relations so recovery can still restore the last confirmed state.
enum TaskRelationDeletion {
    static func removeReferences(to task: TaskRecord, db: Database) throws {
        if let remoteID = task.remoteID {
            try TaskRelationRecord
                .filter(Column("accountID") == task.accountID && Column("otherTaskRemoteID") == remoteID)
                .deleteAll(db)
        }
        let items = try MutationQueueRecord.filter(Column("accountID") == task.accountID)
            .filter(Column("entityType") == MutationEntityType.task.rawValue)
            .filter([MutationOperation.addRelation.rawValue, MutationOperation.removeRelation.rawValue]
                .contains(Column("operation"))).fetchAll(db)
        for item in items {
            let payload = try KanbanLocalMutations.decode(TaskRelationMutationPayload.self, item: item)
            if item.targetLocalID == task.localID || payload.otherTaskLocalID == task.localID {
                try item.delete(db)
            }
        }
    }
}
