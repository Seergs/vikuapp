import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaTaskAttachmentRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyTaskAttachmentRepository(label: "v1")
        let v2 = SpyTaskAttachmentRepository(label: "v2")
        let capabilityProvider = FakeTaskAttachmentCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaTaskAttachmentRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let attachments = try await repository.fetchAttachments(taskID: 1)

        #expect(attachments.first?.fileName == "v1")
        #expect(v1.fetchAttachmentsCallCount == 1)
        #expect(v2.fetchAttachmentsCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyTaskAttachmentRepository(label: "v1")
        let v2 = SpyTaskAttachmentRepository(label: "v2")
        let capabilityProvider = FakeTaskAttachmentCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskAttachmentRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let attachments = try await repository.fetchAttachments(taskID: 1)

        #expect(attachments.first?.fileName == "v2")
        #expect(v1.fetchAttachmentsCallCount == 0)
        #expect(v2.fetchAttachmentsCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every method`() async throws {
        let v1 = SpyTaskAttachmentRepository(label: "v1")
        let v2 = SpyTaskAttachmentRepository(label: "v2")
        let capabilityProvider = FakeTaskAttachmentCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskAttachmentRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        _ = try await repository.uploadAttachment(data: Data(), fileName: "a", mimeType: "text/plain", toTask: 1)
        _ = try await repository.downloadAttachment(1, fromTask: 1, previewSize: nil)
        try await repository.deleteAttachment(1, fromTask: 1)

        #expect(v1.uploadAttachmentCallCount == 0)
        #expect(v1.downloadAttachmentCallCount == 0)
        #expect(v1.deleteAttachmentCallCount == 0)
        #expect(v2.uploadAttachmentCallCount == 1)
        #expect(v2.downloadAttachmentCallCount == 1)
        #expect(v2.deleteAttachmentCallCount == 1)
    }
}

private final class SpyTaskAttachmentRepository: TaskAttachmentRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchAttachmentsCallCount = 0
    private(set) var uploadAttachmentCallCount = 0
    private(set) var downloadAttachmentCallCount = 0
    private(set) var deleteAttachmentCallCount = 0

    init(label: String) {
        self.label = label
    }

    private static let author = User(id: 1, username: "sergio")

    func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        fetchAttachmentsCallCount += 1
        return [TaskAttachment(
            id: 1, taskID: taskID, fileName: label, mimeType: "text/plain",
            sizeBytes: 1, created: .now, createdBy: Self.author,
        )]
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        uploadAttachmentCallCount += 1
        return []
    }

    func downloadAttachment(
        _ id: Int,
        fromTask taskID: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        downloadAttachmentCallCount += 1
        return Data()
    }

    func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        deleteAttachmentCallCount += 1
    }
}

private struct FakeTaskAttachmentCapabilityProvider: CapabilityProvider {
    let supportsAPIV2: Bool

    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "2.4.0", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        switch feature {
        case .apiV2:
            supportsAPIV2
        default:
            false
        }
    }
}
