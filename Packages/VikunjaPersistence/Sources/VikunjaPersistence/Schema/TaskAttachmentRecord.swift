import Foundation
import GRDB
import VikunjaCore

struct TaskAttachmentCatalogRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskAttachmentCatalog"
    var accountID: UUID
    var taskLocalID: UUID
    /// Shared across repository instances so late reads cannot undo a write,
    /// a newer refresh, task deletion, or account cache replacement.
    var revision: UUID
    var lastSuccessfulDownloadAt: Date?
}

struct TaskAttachmentRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskAttachment"
    var accountID: UUID
    var taskLocalID: UUID
    var remoteID: Int
    var position: Int
    var fileName: String
    var mimeType: String
    var sizeBytes: Int
    var created: Date
    var authorID: Int
    var authorUsername: String
    var authorName: String?
    var authorEmail: String?

    init(attachment: TaskAttachment, accountID: UUID, taskLocalID: UUID, position: Int) {
        self.accountID = accountID
        self.taskLocalID = taskLocalID
        self.remoteID = attachment.id
        self.position = position
        self.fileName = attachment.fileName
        self.mimeType = attachment.mimeType
        self.sizeBytes = attachment.sizeBytes
        self.created = attachment.created
        self.authorID = attachment.createdBy.id
        self.authorUsername = attachment.createdBy.username
        self.authorName = attachment.createdBy.name
        self.authorEmail = attachment.createdBy.email
    }

    func attachment(taskID: Int) -> TaskAttachment {
        TaskAttachment(
            id: remoteID, taskID: taskID, fileName: fileName, mimeType: mimeType,
            sizeBytes: sizeBytes, created: created,
            createdBy: User(id: authorID, username: authorUsername, name: authorName, email: authorEmail),
        )
    }
}
