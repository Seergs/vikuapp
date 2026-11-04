import Foundation
import Testing
@testable import WhatsNew

@MainActor
@Suite("What's New images")
struct WhatsNewImageTests {
    private let url = URL(string: "https://imagedelivery.net/account/image/hero")!
    /// A complete one-pixel PNG, rather than arbitrary bytes masquerading as artwork.
    private let png: Data

    init() throws {
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII="
        self.png = try #require(Data(base64Encoded: encoded))
    }

    @Test
    func `existing asset names and HTTPS delivery URLs are supported`() {
        #expect(WhatsNewImageSource("release-art") == .asset("release-art"))
        #expect(WhatsNewImageSource(url.absoluteString) == .remote(url))
        #expect(WhatsNewImageSource(nil) == .placeholder)
        #expect(WhatsNewImageSource("") == .placeholder)
    }

    @Test(arguments: ["http://example.com/image", "file:///image.png", "data:image/png;base64,abc", "//example.com/image", "https://", "https:///image"])
    func `unsupported and malformed URLs use a placeholder`(value: String) {
        #expect(WhatsNewImageSource(value) == .placeholder)
    }

    @Test
    func `downloaded artwork is decoded and cleared when switching to a local image`() async {
        let model = WhatsNewImageViewModel(loader: FakeImageLoader(result: .success(png)))
        await model.load(.remote(url))
        #expect(model.image?.width == 1)
        #expect(model.imageURL == url)
        await model.load(.asset("local-art"))
        #expect(model.image == nil)
        #expect(model.imageURL == nil)
    }

    @Test
    func `invalid image data keeps the placeholder`() async {
        let model = WhatsNewImageViewModel(loader: FakeImageLoader(result: .success(Data("not an image".utf8))))
        await model.load(.remote(url))
        #expect(model.image == nil)
    }

    @Test
    func `download failure keeps the placeholder`() async {
        let model = WhatsNewImageViewModel(loader: FakeImageLoader(result: .failure(URLError(.notConnectedToInternet))))
        await model.load(.remote(url))
        #expect(model.image == nil)
    }

    @Test
    func `cancelled request cannot publish an image even if the loader returns data`() async {
        let model = WhatsNewImageViewModel(loader: FakeImageLoader(result: .success(png)))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(.remote(url))
        }
        await task.value
        #expect(model.image == nil)
    }

    @Test
    func `a slow obsolete request cannot replace the current image`() async {
        let loader = SuspendedImageLoader()
        let model = WhatsNewImageViewModel(loader: loader)
        let task = Task { await model.load(.remote(url)) }
        await loader.waitUntilStarted()
        await model.load(.placeholder)
        await loader.finish(png)
        await task.value
        #expect(model.image == nil)
        #expect(model.imageURL == nil)
    }
}

private struct FakeImageLoader: WhatsNewImageLoading {
    let result: Result<Data, URLError>

    func data(for url: URL) async throws -> Data {
        try result.get()
    }
}

private actor SuspendedImageLoader: WhatsNewImageLoading {
    private var pending: CheckedContinuation<Data, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func data(for url: URL) async throws -> Data {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if pending != nil {
            return
        }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ data: Data) {
        pending?.resume(returning: data)
        pending = nil
    }
}
