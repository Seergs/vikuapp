import Foundation
import GRDB

/// Reject a download started before a local write or upload acknowledgement.
/// The account worker normally serializes sync; local commands can still commit during network reads.
struct KanbanReadState: Equatable, Sendable {
    let tasks: [TaskRecord]
    let assignments: [KanbanAssignmentRecord]
    let mutations: [MutationQueueRecord]

    init(accountID: UUID, projectID: UUID, db: Database) throws {
        self.tasks = try TaskRecord.filter(Column("accountID") == accountID)
            .filter(Column("projectLocalID") == projectID).order(Column("localID")).fetchAll(db)
        self.assignments = try KanbanAssignmentRecord.filter(Column("accountID") == accountID)
            .filter(Column("projectLocalID") == projectID)
            .order(Column("viewLocalID"), Column("taskLocalID")).fetchAll(db)
        self.mutations = try MutationQueueRecord.filter(Column("accountID") == accountID)
            .filter(Column("entityType") == MutationEntityType.task.rawValue).order(Column("id")).fetchAll(db)
    }
}
