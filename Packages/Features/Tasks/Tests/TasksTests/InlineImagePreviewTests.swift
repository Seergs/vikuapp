import CoreGraphics
import Foundation
import ImageIO
@testable import Tasks
import Testing
import UniformTypeIdentifiers
import VikuDesignSystem
import VikunjaCore

@MainActor
@Suite("TaskDetailViewModel inline images")
struct InlineImagePreviewTests {
    private static let image = RichTextImage(
        source: "https://vikunja.example.com/api/v1/tasks/284/attachments/8", alt: "Whiteboard",
    )

    @Test
    func `opens the original of an embedded image as a typed file`() async throws {
        let loader = try FakeInlineImageLoader(result: .success(Self.png()))
        let viewModel = makeViewModel(loader: loader)

        let url = try #require(await viewModel.inlineImagePreviewURL(for: Self.image))

        #expect(url.lastPathComponent == "Whiteboard.png")
        #expect(try Data(contentsOf: url) == Self.png())
        #expect(await loader.requests == [.init(source: Self.image.source, variant: .original)])
    }

    @Test
    func `names an image without alt text generically`() async throws {
        let loader = try FakeInlineImageLoader(result: .success(Self.png()))
        let viewModel = makeViewModel(loader: loader)

        let url = try #require(await viewModel.inlineImagePreviewURL(
            for: RichTextImage(source: Self.image.source),
        ))

        #expect(url.lastPathComponent == "Image.png")
    }

    @Test
    func `reports a failed download instead of opening an empty preview`() async {
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(
            loader: FakeInlineImageLoader(result: .failure(VikunjaError.offline)), toast: toast,
        )

        let url = await viewModel.inlineImagePreviewURL(for: Self.image)

        #expect(url == nil)
        #expect(toast.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `does nothing without a loader`() async {
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(loader: nil, toast: toast)

        #expect(await viewModel.inlineImagePreviewURL(for: Self.image) == nil)
        #expect(toast.shownMessages.isEmpty)
    }

    private func makeViewModel(
        loader: FakeInlineImageLoader?,
        toast: FakeToastPresenter = FakeToastPresenter(),
    ) -> TaskDetailViewModel {
        TaskDetailViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            task: VikunjaTask(id: 284, title: "Plan", projectID: 1),
            project: Project(id: 1, title: "Work"), repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(), attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(), toastPresenter: toast,
            inlineImageLoader: loader,
        )
    }

    private static func png() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil),
        )
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }
}

private actor FakeInlineImageLoader: InlineImageLoading {
    struct Request: Equatable {
        let source: String
        let variant: InlineImageVariant
    }

    private let result: Result<Data, Error>
    private(set) var requests: [Request] = []

    init(result: Result<Data, Error>) {
        self.result = result
    }

    func imageData(for source: String, variant: InlineImageVariant) throws -> Data {
        requests.append(Request(source: source, variant: variant))
        return try result.get()
    }
}
