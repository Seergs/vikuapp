import Foundation
import GRDB
import VikunjaCore

enum KanbanCapacity {
    /// Matches the board's visible occupancy, including local-only tasks.
    static func check(_ bucket: KanbanBucketRecord, excluding taskID: UUID? = nil, db: Database) throws {
        guard bucket.limit > 0 else { return }
        let hidden = try Set(MutationQueueRecord.filter(Column("accountID") == bucket.accountID)
            .fetchAll(db).filter { $0.entityType == .task && $0.operation == .delete }.map(\.targetLocalID))
        let count = try KanbanAssignmentRecord.filter(Column("bucketLocalID") == bucket.localID)
            .fetchAll(db).filter { $0.taskLocalID != taskID && !hidden.contains($0.taskLocalID) }.count
        guard count < bucket.limit else { throw VikunjaError.bucketFull }
    }
}
