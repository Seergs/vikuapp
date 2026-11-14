import Foundation
import VikunjaCore

public final class VikunjaTaskAttachmentRepository: TaskAttachmentRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        let dtos: [TaskAttachmentDTO] = try await client.sendAllPagesV1 {
            VikunjaEndpoints.taskAttachments(taskID: taskID, page: $0)
        }
        return dtos.map(AttachmentMapper.toDomain)
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
            VikunjaEndpoints.uploadTaskAttachment(taskID: taskID, form: form),
        )
        return (result.success ?? []).map(AttachmentMapper.toDomain)
    }

    public func downloadAttachment(
        _ id: Int,
        fromTask taskID: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        try await client.data(
            VikunjaEndpoints.downloadTaskAttachment(taskID: taskID, attachmentID: id, previewSize: previewSize),
        )
    }

    public func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteTaskAttachment(taskID: taskID, attachmentID: id))
    }
}
