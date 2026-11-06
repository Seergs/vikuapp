import Foundation
import Testing
@testable import VikunjaCore

@Suite("InlineImageLoader")
struct InlineImageLoaderTests {
    private static let instance = URL(string: "https://vikunja.example.com")!
    private static let attachmentSource = "https://vikunja.example.com/api/v1/tasks/284/attachments/8"

    private func makeLoader(
        repository: RecordingAttachmentRepository,
        remote: RecordingRemoteFetch = RecordingRemoteFetch(),
    ) -> InlineImageLoader {
        InlineImageLoader(instanceURL: Self.instance, attachmentRepository: repository) { url in
            await remote.fetch(url)
        }
    }

    @Test
    func `downloads the xl preview of an attachment for display`() async throws {
        let repository = RecordingAttachmentRepository()
        let loader = makeLoader(repository: repository)

        let data = try await loader.imageData(for: Self.attachmentSource, variant: .display)

        #expect(data == Data("xl".utf8))
        #expect(await repository.requests == [.init(taskID: 284, attachmentID: 8, size: .xl)])
    }

    @Test
    func `downloads the original for the full-screen viewer`() async throws {
        let repository = RecordingAttachmentRepository()
        let loader = makeLoader(repository: repository)

        let data = try await loader.imageData(for: Self.attachmentSource, variant: .original)

        #expect(data == Data("original".utf8))
        #expect(await repository.requests == [.init(taskID: 284, attachmentID: 8, size: nil)])
    }

    @Test
    func `falls back to the original when the server can't render a preview`() async throws {
        let repository = RecordingAttachmentRepository()
        await repository.failPreviews(with: .server(message: "not previewable", statusCode: 412))
        let loader = makeLoader(repository: repository)

        let data = try await loader.imageData(for: Self.attachmentSource, variant: .display)

        #expect(data == Data("original".utf8))
        #expect(await repository.requests.map(\.size) == [.xl, nil])
    }

    @Test
    func `does not retry the original when offline`() async {
        let repository = RecordingAttachmentRepository()
        await repository.failPreviews(with: .offline)
        let loader = makeLoader(repository: repository)

        await #expect(throws: VikunjaError.offline) {
            try await loader.imageData(for: Self.attachmentSource, variant: .display)
        }
        #expect(await repository.requests.map(\.size) == [.xl])
    }

    @Test
    func `serves a repeated request from memory`() async throws {
        let repository = RecordingAttachmentRepository()
        let loader = makeLoader(repository: repository)

        _ = try await loader.imageData(for: Self.attachmentSource, variant: .display)
        _ = try await loader.imageData(for: Self.attachmentSource, variant: .display)

        #expect(await repository.requests.count == 1)
    }

    @Test
    func `reuses a cached original for display`() async throws {
        let repository = RecordingAttachmentRepository()
        let loader = makeLoader(repository: repository)

        _ = try await loader.imageData(for: Self.attachmentSource, variant: .original)
        let display = try await loader.imageData(for: Self.attachmentSource, variant: .display)

        #expect(display == Data("original".utf8))
        #expect(await repository.requests.count == 1)
    }

    @Test
    func `shares one download between concurrent requests`() async throws {
        let repository = RecordingAttachmentRepository()
        await repository.holdResponses()
        let loader = makeLoader(repository: repository)

        async let first = loader.imageData(for: Self.attachmentSource, variant: .display)
        async let second = loader.imageData(for: Self.attachmentSource, variant: .display)
        while await repository.requests.isEmpty {
            await Task.yield()
        }
        await repository.releaseResponses()

        let results = try await [first, second]
        #expect(results == [Data("xl".utf8), Data("xl".utf8)])
        #expect(await repository.requests.count == 1)
    }

    @Test
    func `does not cache a failure`() async throws {
        let repository = RecordingAttachmentRepository()
        await repository.failAll(with: .offline)
        let loader = makeLoader(repository: repository)

        await #expect(throws: VikunjaError.offline) {
            try await loader.imageData(for: Self.attachmentSource, variant: .original)
        }
        await repository.failAll(with: nil)
        let data = try await loader.imageData(for: Self.attachmentSource, variant: .original)

        #expect(data == Data("original".utf8))
    }

    @Test
    func `fetches a remote image without the attachment endpoint`() async throws {
        let repository = RecordingAttachmentRepository()
        let remote = RecordingRemoteFetch()
        let loader = makeLoader(repository: repository, remote: remote)

        _ = try await loader.imageData(for: "https://images.example.org/cat.png", variant: .display)
        _ = try await loader.imageData(for: "https://images.example.org/cat.png", variant: .original)

        #expect(try await remote.urls == [#require(URL(string: "https://images.example.org/cat.png"))])
        #expect(await repository.requests.isEmpty)
    }

    @Test
    func `refuses a source it can't load safely`() async {
        let repository = RecordingAttachmentRepository()
        let remote = RecordingRemoteFetch()
        let loader = makeLoader(repository: repository, remote: remote)

        await #expect(throws: InlineImageLoadingError.unsupportedSource) {
            try await loader.imageData(
                for: "https://other.example.com/api/v1/tasks/284/attachments/8", variant: .display,
            )
        }
        #expect(await repository.requests.isEmpty)
        #expect(await remote.urls.isEmpty)
    }
}

private actor RecordingRemoteFetch {
    private(set) var urls: [URL] = []

    func fetch(_ url: URL) -> Data {
        urls.append(url)
        return Data("remote".utf8)
    }
}

private actor RecordingAttachmentRepository: TaskAttachmentRepositoryProtocol {
    struct Request: Equatable {
        let taskID: Int
        let attachmentID: Int
        let size: AttachmentPreviewSize?
    }

    private(set) var requests: [Request] = []
    private var previewError: VikunjaError?
    private var allError: VikunjaError?
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    func failPreviews(with error: VikunjaError) {
        previewError = error
    }

    func failAll(with error: VikunjaError?) {
        allError = error
    }

    func holdResponses() {
        isHolding = true
    }

    func releaseResponses() {
        isHolding = false
        held.forEach { $0.resume() }
        held.removeAll()
    }

    func downloadAttachment(_ id: Int, fromTask taskID: Int, previewSize: AttachmentPreviewSize?) async throws -> Data {
        requests.append(Request(taskID: taskID, attachmentID: id, size: previewSize))
        if isHolding {
            await withCheckedContinuation { held.append($0) }
        }
        if let allError {
            throw allError
        }
        if previewSize != nil, let previewError {
            throw previewError
        }
        return Data((previewSize?.rawValue ?? "original").utf8)
    }

    func fetchAttachments(taskID _: Int) async throws -> [TaskAttachment] {
        []
    }

    func uploadAttachment(data _: Data, fileName _: String, mimeType _: String, toTask _: Int) async throws -> [TaskAttachment] {
        []
    }

    func deleteAttachment(_: Int, fromTask _: Int) async throws {}
}
