import Foundation
import VikunjaCore

/// Routes each `TaskAttachmentRepositoryProtocol` call to the v1 or v2
/// concrete repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource).
final class VikunjaTaskAttachmentRepositorySwitch: TaskAttachmentRepositoryProtocol {
    private let v1: TaskAttachmentRepositoryProtocol
    private let v2: TaskAttachmentRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(
        v1: TaskAttachmentRepositoryProtocol,
        v2: TaskAttachmentRepositoryProtocol,
        capabilityProvider: CapabilityProvider,
    ) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> TaskAttachmentRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        try await resolve().fetchAttachments(taskID: taskID)
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        try await resolve().uploadAttachment(data: data, fileName: fileName, mimeType: mimeType, toTask: taskID)
    }

    func downloadAttachment(
        _ id: Int,
        fromTask taskID: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        try await resolve().downloadAttachment(id, fromTask: taskID, previewSize: previewSize)
    }

    func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        try await resolve().deleteAttachment(id, fromTask: taskID)
    }
}
