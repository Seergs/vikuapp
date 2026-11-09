import Foundation
import os
import VikunjaCore

/// Temporary debug diagnostics. Only identities and timestamps are logged;
/// comment bodies, authors, credentials, and server URLs are excluded.
enum CommentOrderDiagnostics {
    private static let logger = Logger(subsystem: "dev.sergiosuarez.vikunja", category: "comment-order")

    static func rows(_ event: String, _ rows: [TaskCommentRecord]) {
        #if DEBUG
        for (index, row) in rows.enumerated() {
            self.row(event, row, index: index)
        }
        #endif
    }

    static func serverOrder(_ comments: [TaskComment], accountID: UUID, taskLocalID: UUID) {
        #if DEBUG
        for (index, comment) in comments.enumerated() {
            remote("pull.server-order", comment, accountID: accountID, taskLocalID: taskLocalID, index: index)
        }
        #endif
    }

    static func row(_ event: String, _ row: TaskCommentRecord, index: Int? = nil) {
        #if DEBUG
        logger.debug("[comment-order] \(event, privacy: .public) account=\(row.accountID.uuidString, privacy: .public) taskLocal=\(row.taskLocalID.uuidString, privacy: .public) index=\(index ?? -1) local=\(row.localID.uuidString, privacy: .public) remote=\(row.remoteID ?? -1) created=\(String(row.created.timeIntervalSince1970), privacy: .public) updated=\(String(row.updated.timeIntervalSince1970), privacy: .public)")
        #endif
    }

    static func remote(_ event: String, _ comment: TaskComment, accountID: UUID, taskLocalID: UUID, index: Int? = nil) {
        #if DEBUG
        logger.debug("[comment-order] \(event, privacy: .public) account=\(accountID.uuidString, privacy: .public) taskLocal=\(taskLocalID.uuidString, privacy: .public) index=\(index ?? -1) remote=\(comment.id.remoteValue ?? -1) created=\(String(comment.created.timeIntervalSince1970), privacy: .public) updated=\(String(comment.updated.timeIntervalSince1970), privacy: .public)")
        #endif
    }
}
