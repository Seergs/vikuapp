import Foundation

actor RequestCapture {
    private(set) var requests: [URLRequest] = []

    var lastRequest: URLRequest? {
        requests.last
    }

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

final class MockURLProtocol: URLProtocol {
    private struct Response {
        let statusCode: Int
        let body: Data
        let headers: [String: String]
    }

    private nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var capture: RequestCapture?

    /// Single canned response reused for every request the session makes.
    static func makeSession(statusCode: Int, body: String, headers: [String: String] = [:]) -> (URLSession, RequestCapture) {
        makeSession(responses: [Response(statusCode: statusCode, body: Data(body.utf8), headers: headers)])
    }

    /// One response per request, consumed in order — for a call that issues
    /// more than one request (e.g. `VikunjaTaskRepository.update(_:)`'s
    /// GET-then-POST safe-update) and each leg needs its own reply. The last
    /// queued response repeats if more requests arrive than were queued.
    static func makeSession(responses: [(statusCode: Int, body: String)]) -> (URLSession, RequestCapture) {
        let mapped = responses.map { Response(statusCode: $0.statusCode, body: Data($0.body.utf8), headers: [:]) }
        return makeSession(responses: mapped)
    }

    private static func makeSession(responses: [Response]) -> (URLSession, RequestCapture) {
        let capture = RequestCapture()
        Self.responses = responses
        Self.capture = capture

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return (URLSession(configuration: configuration), capture)
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
        // `URLSession` moves a POST/PUT body into `httpBodyStream` when
        // dispatching through a custom `URLProtocol`, leaving `httpBody`
        // nil — read the stream now (it can only be consumed once) so
        // callers inspecting the captured request's body don't see nil.
        var request = request
        if request.httpBody == nil, let bodyData = Self.readBody(from: request) {
            request.httpBody = bodyData
        }
        // A fresh `let` snapshot to hand to the `Task` below — capturing
        // the `var` itself trips Swift 6's strict-concurrency "sending"
        // check, since this function keeps using `request` afterward.
        let capturedRequest = request
        let capture = Self.capture
        // Block until the capture actor has recorded the request: without this,
        // `record(_:)` races the response we deliver below, so a test's `await
        // capture.lastRequest` right after its network call can read `nil` if the
        // recording `Task` hasn't been scheduled yet.
        let recorded = DispatchSemaphore(value: 0)
        Task {
            await capture?.record(capturedRequest)
            recorded.signal()
        }
        recorded.wait()

        let response: Response = if Self.responses.count > 1 {
            Self.responses.removeFirst()
        } else if let only = Self.responses.first {
            only
        } else {
            Response(statusCode: 200, body: Data(), headers: [:])
        }

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: response.headers,
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
