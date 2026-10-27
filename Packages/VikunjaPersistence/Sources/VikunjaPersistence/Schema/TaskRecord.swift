import Foundation
import GRDB

/// Row shape of the `task` table: the local cache of a task's core fields —
/// everything `TaskListMutator`/`TaskDetailViewModel` already optimistically
/// mutate today (title, description, done, due date, priority). Labels,
/// relations, comments, and attachments are Slice 4's concern, not this
/// table's. Mapping to/from the `VikunjaCore.VikunjaTask` domain model
/// belongs to the repository that reads/writes this record, not here.
struct TaskRecord: Codable, Equatable, Sendable {
    var localID: UUID
    var accountID: UUID
    var remoteID: Int?
    var title: String
    var description: String?
    var isDone: Bool
    var dueDate: Date?
    var priority: Int
    /// The owning project's local id — resolved the same way a sub-project's
    /// `parentProjectLocalID` is, so a task created offline under a project
    /// that's also only local-so-far still has somewhere to point until both
    /// sync. Unlike a project's parent, never nil: every task belongs to
    /// exactly one project.
    var projectLocalID: UUID
}

extension TaskRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "task"
}
