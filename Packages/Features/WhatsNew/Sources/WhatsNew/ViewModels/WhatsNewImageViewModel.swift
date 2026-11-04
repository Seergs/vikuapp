import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class WhatsNewImageViewModel {
    private(set) var image: CGImage?
    private(set) var imageURL: URL?
    private let loader: any WhatsNewImageLoading
    private var requestID = UUID()

    init(loader: any WhatsNewImageLoading = WhatsNewImageLoader.shared) {
        self.loader = loader
    }

    func load(_ source: WhatsNewImageSource) async {
        let id = UUID()
        requestID = id
        image = nil
        imageURL = nil
        guard case let .remote(url) = source else { return }
        do {
            let data = try await loader.data(for: url)
            try Task.checkCancellation()
            guard requestID == id,
                  let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return }
            // Bound decoded memory even if the content points at an oversized original.
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
            ] as CFDictionary)
            imageURL = url
        } catch {
            // Artwork is optional: failure and cancellation preserve the placeholder.
        }
    }
}
