import Foundation
@testable import VikunjaNetworking

/// Cancel deterministically after a decoded response, including the final page.
actor PaginationCancellationClient: APIClient {
    let base: any APIClient
    let cancelAfterPage: Int
    private var requests = 0

    init(base: any APIClient, cancelAfterPage: Int) {
        self.base = base
        self.cancelAfterPage = cancelAfterPage
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        let result: Response = try await base.send(endpoint)
        cancelIfNeeded()
        return result
    }

    func sendWithResponse<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (Response, HTTPURLResponse) {
        let result: (Response, HTTPURLResponse) = try await base.sendWithResponse(endpoint)
        cancelIfNeeded()
        return result
    }

    func send(_ endpoint: Endpoint) async throws {
        try await base.send(endpoint)
    }

    func data(_ endpoint: Endpoint) async throws -> Data {
        try await base.data(endpoint)
    }

    private func cancelIfNeeded() {
        requests += 1
        if requests == cancelAfterPage {
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
}
