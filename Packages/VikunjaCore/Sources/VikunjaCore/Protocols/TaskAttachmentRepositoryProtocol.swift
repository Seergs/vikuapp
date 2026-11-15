import Foundation

/// One task's attachments: list, upload, download, delete. Kept separate from
/// `TaskRepositoryProtocol` because Vikunja serves each through its own
/// endpoint (`/tasks/{id}/attachments`), the same split `TaskCommentRepositoryProtocol`
/// has.
public protocol TaskAttachmentRepositoryProtocol: Sendable {
    /// Reads persisted metadata only. Nil means this task has no saved catalog.
    func cachedAttachmentSnapshot(taskID: Int) async throws -> TaskAttachmentSnapshot?

    /// Downloads the complete catalog and replaces any persisted metadata atomically.
    func fetchAttachments(taskID: Int) async throws -> [TaskAttachment]

    /// Uploads one file. Vikunja's endpoint accepts and echoes back several at
    /// once (multipart field `files`), so the result is an array even though
    /// callers upload one at a time.
    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        toTask taskID: Int,
    ) async throws -> [TaskAttachment]

    /// Returns the attachment's raw bytes. `previewSize` requests a scaled
    /// image rendition instead of the original (ignored server-side for
    /// non-images).
    func downloadAttachment(
        _ id: Int,
        fromTask taskID: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data

    func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws
}

public extension TaskAttachmentRepositoryProtocol {
    /// Transport-only repositories have no local metadata store.
    func cachedAttachmentSnapshot(taskID: Int) async throws -> TaskAttachmentSnapshot? {
        nil
    }
}
