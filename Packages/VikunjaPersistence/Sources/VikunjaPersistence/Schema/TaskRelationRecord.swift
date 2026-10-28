import Foundation
import GRDB
import VikunjaCore

/// Row shape of the `taskRelation` table: one confirmed relation from
/// `taskLocalID`'s perspective to another task, as of the last pull or the
/// last successful `addRelation`/`removeRelation` drain. Always references
/// the other task by its remote id — this table only ever gets written from
/// a server response (a pull, or a push's own success), and the other task
/// is never still local-only at that point (`drainTaskRelationMutation`
/// resolves both sides to remote ids before pushing). A relation queued but
/// not yet drained is resolved separately, from the mutation queue — see
/// `OfflineTaskRepository`'s own relation-assembly code.
///
/// Carries the other task's display fields (title, done, project) rather
/// than joining against `task` at read time, since the other task isn't
/// guaranteed to be cached locally itself (e.g. it lives in a project this
/// account hasn't pulled, or was never otherwise fetched on its own).
struct TaskRelationRecord: Codable, Equatable, Sendable {
    var localID: UUID
    var accountID: UUID
    var taskLocalID: UUID
    var kind: RelationKind
    var otherTaskRemoteID: Int
    var otherProjectRemoteID: Int
    var title: String
    var isDone: Bool
}

extension TaskRelationRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskRelation"
}
