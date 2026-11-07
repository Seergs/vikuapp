import Foundation

/// One consistent local view of a conversation and its download coverage.
/// A nil date means the complete server conversation has never been downloaded,
/// even when locally created or legacy cached comments are present.
public struct TaskCommentSnapshot: Sendable {
    public let comments: [TaskComment]
    public let lastSuccessfulDownloadAt: Date?
    /// A task not yet created on the server has no remote conversation to download.
    public let isLocalOnly: Bool

    public init(comments: [TaskComment], lastSuccessfulDownloadAt: Date?, isLocalOnly: Bool = false) {
        self.comments = comments
        self.lastSuccessfulDownloadAt = lastSuccessfulDownloadAt
        self.isLocalOnly = isLocalOnly
    }
}
