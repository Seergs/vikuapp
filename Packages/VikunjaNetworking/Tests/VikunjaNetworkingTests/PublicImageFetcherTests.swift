import Foundation
import Testing
@testable import VikunjaNetworking

/// Lives in the `.serialized` `URLSessionAPIClientTests` suite because it
/// shares `MockURLProtocol`'s static state.
extension URLSessionAPIClientTests {
    private static let imageURL = URL(string: "https://images.example.org/cat.png")!

    @Test
    func `public image fetch returns the bytes without credentials`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: "png-bytes", headers: ["Content-Type": "image/png"],
        )

        let data = try await PublicImageFetcher(session: session).fetch(Self.imageURL)

        #expect(data == Data("png-bytes".utf8))
        let request = await capture.lastRequest
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request?.value(forHTTPHeaderField: "Accept") == "image/*")
    }

    @Test
    func `public image fetch rejects an error status`() async {
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 404, body: "missing", headers: ["Content-Type": "image/png"],
        )

        await #expect(throws: PublicImageFetcher.FetchError.badStatus(404)) {
            try await PublicImageFetcher(session: session).fetch(Self.imageURL)
        }
    }

    @Test
    func `public image fetch rejects a response that is not an image`() async {
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200, body: "<html>login</html>", headers: ["Content-Type": "text/html"],
        )

        await #expect(throws: PublicImageFetcher.FetchError.notAnImage) {
            try await PublicImageFetcher(session: session).fetch(Self.imageURL)
        }
    }
}
