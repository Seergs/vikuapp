import Foundation
import GRDB

/// Coverage of a complete conversation download, including an empty response.
struct TaskCommentSyncRecord: Codable, Equatable, Sendable {
    var accountID: UUID
    var taskLocalID: UUID
    var lastSuccessfulDownloadAt: Date
}

extension TaskCommentSyncRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskCommentSync"
}
