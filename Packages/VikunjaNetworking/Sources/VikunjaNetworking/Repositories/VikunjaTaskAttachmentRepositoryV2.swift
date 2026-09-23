import Foundation
import VikunjaCore

/// v2 implementation of `TaskAttachmentRepositoryProtocol`. Reuses v1's
/// `TaskAttachmentDTO` / `FileDTO` / `AttachmentUploadResultDTO` /
/// `AttachmentMapper` rather than adding new ones — verified against a real
/// instance's `/api/v2/openapi.json`: v2's `TaskAttachment`/`File`/
/// `AttachmentUploadResult`/`AttachmentUploadError` schemas match those DTOs
/// field for field (including `AttachmentUploadError.code` already being an
/// `Int`, unlike `ProblemDetailDTO.code`'s pre-migration bug — see
/// `AttachmentUploadErrorDTO`). Multipart upload keeps the same `"files"`
/// field and raw-bytes download; only the verb changes (`POST`, not `PUT`).
public final class VikunjaTaskAttachmentRepositoryV2: TaskAttachmentRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        let envelope: APIv2Envelope<TaskAttachmentDTO> = try await client.send(
            VikunjaEndpoints.taskAttachmentsV2(taskID: taskID),
        )
        return envelope.items.map(AttachmentMapper.toDomain)
    }

    public func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        var form = MultipartFormData()
        form.addFile(name: "files", fileName: fileName, mimeType: mimeType, data: data)
        let result: AttachmentUploadResultDTO = try await client.send(
            VikunjaEndpoints.uploadTaskAttachmentV2(taskID: taskID, form: form),
        )
        return (result.success ?? []).map(AttachmentMapper.toDomain)
    }

    public func downloadAttachment(
        _ id: Int,
        fromTask taskID: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        try await client.data(
            VikunjaEndpoints.downloadTaskAttachmentV2(taskID: taskID, attachmentID: id, previewSize: previewSize),
        )
    }

    public func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteTaskAttachmentV2(taskID: taskID, attachmentID: id))
    }
}
