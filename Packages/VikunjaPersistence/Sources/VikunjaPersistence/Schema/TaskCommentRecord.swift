import Foundation
import GRDB

/// Row shape of the `taskComment` table: the local cache of one comment on a
/// task. Author fields are denormalized rather than joined against a user
/// table (there isn't one) so an offline-created comment still has enough
/// identity to render before the server has ever seen it.
struct TaskCommentRecord: Codable, Equatable, Sendable {
    var localID: UUID
    var accountID: UUID
    var remoteID: Int?
    /// The owning task's local id. Kept local (not remote) so a comment
    /// queued against a task created offline survives that task's own create
    /// resolving to a real server id.
    var taskLocalID: UUID
    var comment: String
    var authorID: Int
    var authorUsername: String
    var authorName: String?
    var authorEmail: String?
    var created: Date
    var updated: Date
}

extension TaskCommentRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskComment"
}
