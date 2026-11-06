import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VikuDesignSystem

@Suite("RichTextImageDecoder")
struct RichTextImageDecoderTests {
    @Test
    func `downsamples a large image to the pixel cap`() async throws {
        let data = try Self.png(width: 400, height: 200)

        let decoded = try #require(await RichTextImageDecoder.decode(data, maxPixelSize: 100))

        #expect(decoded.cgImage.width == 100)
        #expect(decoded.cgImage.height == 50)
    }

    @Test
    func `keeps a small image at its own size`() async throws {
        let data = try Self.png(width: 40, height: 30)

        let decoded = try #require(await RichTextImageDecoder.decode(data, maxPixelSize: 2048))

        #expect(decoded.cgImage.width == 40)
        #expect(decoded.cgImage.height == 30)
    }

    @Test
    func `returns nil for bytes that are not an image`() async {
        #expect(await RichTextImageDecoder.decode(Data("<html>401</html>".utf8), maxPixelSize: 100) == nil)
    }

    private static func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil),
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
