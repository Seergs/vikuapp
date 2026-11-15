import Foundation

/// Metadata only; file contents are downloaded separately on demand.
public struct TaskAttachmentSnapshot: Equatable, Sendable {
    public let attachments: [TaskAttachment]
    /// Nil until a complete catalog has been downloaded. Uploading one file
    /// establishes its metadata, but says nothing about the rest of the catalog.
    public let lastSuccessfulDownloadAt: Date?

    public init(attachments: [TaskAttachment], lastSuccessfulDownloadAt: Date?) {
        self.attachments = attachments
        self.lastSuccessfulDownloadAt = lastSuccessfulDownloadAt
    }
}
