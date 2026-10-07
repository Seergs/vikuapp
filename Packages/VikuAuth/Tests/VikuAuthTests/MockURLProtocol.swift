import Foundation

/// A minimal stand-in for a real relay response — queued per test, consumed
/// in order, with the last one repeating if more requests arrive than were
/// queued. Mirrors `VikunjaNetworkingTests.MockURLProtocol`'s shape; kept as
/// its own small copy here rather than a cross-package test dependency.
final class MockURLProtocol: URLProtocol {
    private struct Response {
        let statusCode: Int
        let body: Data
    }

    private nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func makeSession(responses: [(statusCode: Int, body: String)]) -> URLSession {
        Self.responses = responses.map { Response(statusCode: $0.statusCode, body: Data($0.body.utf8)) }
        capturedRequests = []

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var request = request
        if request.httpBody == nil, let bodyData = Self.readBody(from: request) {
            request.httpBody = bodyData
        }
        Self.capturedRequests.append(request)

        let response: Response = if Self.responses.count > 1 {
            Self.responses.removeFirst()
        } else if let only = Self.responses.first {
            only
        } else {
            Response(statusCode: 200, body: Data())
        }

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: [:],
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
