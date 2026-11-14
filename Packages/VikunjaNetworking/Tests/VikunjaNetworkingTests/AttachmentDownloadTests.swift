import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// HTTP fixtures share MockURLProtocol state, so these belong to the serialized suite.
extension URLSessionAPIClientTests {
    @Test(arguments: [false, true], [20, 50])
    func `attachment catalog includes every page beyond fifty attachments`(v2: Bool, pageSize: Int) async throws {
        let templates = try attachmentDownloadFixture()
        let items = (1 ... 53).map { id in
            var item = templates[(id - 1) % templates.count]
            item["id"] = id
            return item
        }
        let responses = try stride(from: 0, to: items.count, by: pageSize).enumerated().map { index, offset in
            try MockURLProtocol.ScriptedResponse(
                statusCode: 200,
                body: attachmentPageBody(
                    items: Array(items[offset ..< min(offset + pageSize, items.count)]),
                    page: index + 1, total: items.count, perPage: pageSize, v2: v2,
                ),
                headers: ["x-pagination-total-pages": String((items.count + pageSize - 1) / pageSize)],
            )
        }
        let (session, capture) = MockURLProtocol.makeSession(responses: responses)
        let attachments = try await attachmentDownloadRepository(session: session, v2: v2).fetchAttachments(taskID: 42)

        #expect(attachments.map(\.id) == Array(1 ... 53))
        #expect(attachments.allSatisfy { $0.taskID == 42 })
        #expect(attachments.first?.fileName == "design-spec.pdf")
        #expect(attachments.first?.mimeType == "application/pdf")
        #expect(attachments.first?.sizeBytes == 284_736)
        #expect(attachments.first?.createdBy == User(id: 7, username: "alex", name: "Alex"))
        #expect(attachments[1].fileName == "screenshot.png")
        let requests = await capture.requests
        #expect(requests.count == responses.count)
        for (index, request) in requests.enumerated() {
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/\(v2 ? "v2" : "v1")/tasks/42/attachments")
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(query == [URLQueryItem(name: "page", value: String(index + 1))])
        }
    }

    @Test(arguments: [false, true])
    func `single attachment page is returned without extra requests`(v2: Bool) async throws {
        let fixture = try attachmentDownloadFixture()
        let body = try attachmentPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: v2)
        // Some v1 responses omit pagination headers for a single-page result.
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let attachments = try await attachmentDownloadRepository(session: session, v2: v2).fetchAttachments(taskID: 42)
        #expect(attachments.count == fixture.count)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `empty attachment catalog makes only one request`(v2: Bool) async throws {
        let body = v2 ? #"{"items":null,"total":0,"page":1,"per_page":50,"total_pages":0}"# : "[]"
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": "0"],
        )
        let repository = try attachmentDownloadRepository(session: session, v2: v2)
        #expect(try await repository.fetchAttachments(taskID: 42).isEmpty)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true], [200, 403])
    func `later attachment page failure never returns a partial catalog`(v2: Bool, status: Int) async throws {
        let items = try attachmentDownloadFixture()
        let first = try attachmentPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: status, body: "Invalid response"),
        ])
        await #expect(throws: (any Error).self) {
            try await attachmentDownloadRepository(session: session, v2: v2).fetchAttachments(taskID: 42)
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `unexpected empty attachment page is an incomplete download`(v2: Bool) async throws {
        let items = try attachmentDownloadFixture()
        let first = try attachmentPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let second = try attachmentPageBody(items: [], page: 2, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: 200, body: second),
        ])
        await #expect(throws: VikunjaError.self) {
            try await attachmentDownloadRepository(session: session, v2: v2).fetchAttachments(taskID: 42)
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true], [1, 2])
    func `cancelled attachment download never publishes a catalog`(v2: Bool, cancelAfterPage: Int) async throws {
        let items = try attachmentDownloadFixture()
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: attachmentPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: attachmentPageBody(items: [items[0]], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        let base = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let client = AttachmentCancellationClient(base: base, cancelAfterPage: cancelAfterPage)
        let repository: any TaskAttachmentRepositoryProtocol = v2
            ? VikunjaTaskAttachmentRepositoryV2(client: client) : VikunjaTaskAttachmentRepository(client: client)
        let download = Task { try await repository.fetchAttachments(taskID: 42) }
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await capture.requests.count == cancelAfterPage)
    }

    @Test(arguments: ["-1", "invalid"])
    func `invalid v1 attachment pagination is not treated as a complete catalog`(header: String) async throws {
        let fixture = try attachmentDownloadFixture()
        let body = try attachmentPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: false)
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": header],
        )
        await #expect(throws: VikunjaError.self) {
            try await attachmentDownloadRepository(session: session, v2: false).fetchAttachments(taskID: 42)
        }
    }

    @Test(arguments: ["page", "total", "total_pages", "items"])
    func `inconsistent v2 attachment pagination is not a complete catalog`(field: String) async throws {
        let template = try #require(attachmentDownloadFixture().first)
        let items = (1 ... 4).map { id in
            var item = template
            item["id"] = id
            return item
        }
        let first = try attachmentPageBody(items: Array(items.prefix(2)), page: 1, total: 4, perPage: 2, v2: true)
        let second = try attachmentPageBody(items: Array(items.suffix(2)), page: 2, total: 4, perPage: 2, v2: true)
        var object = try #require(JSONSerialization.jsonObject(with: Data(second.utf8)) as? [String: Any])
        if field == "items" {
            object[field] = [items[0]]
        } else {
            object[field] = 1
        }
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        let (session, _) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first),
            .init(statusCode: 200, body: body),
        ])
        await #expect(throws: VikunjaError.self) {
            try await attachmentDownloadRepository(session: session, v2: true).fetchAttachments(taskID: 42)
        }
    }

    private func attachmentDownloadFixture() throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "task-attachments", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    private func attachmentPageBody(items: [[String: Any]], page: Int, total: Int, perPage: Int, v2: Bool) throws -> String {
        let value: Any = v2
            ? [
                "items": items,
                "total": total,
                "page": page,
                "per_page": perPage,
                "total_pages": (total + perPage - 1) / perPage,
            ]
            : items
        return try #require(String(data: JSONSerialization.data(withJSONObject: value), encoding: .utf8))
    }

    private func attachmentDownloadRepository(session: URLSession, v2: Bool) throws -> any TaskAttachmentRepositoryProtocol {
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        return v2 ? VikunjaTaskAttachmentRepositoryV2(client: client) : VikunjaTaskAttachmentRepository(client: client)
    }
}

/// Cancel deterministically after a decoded response, including the final page.
private actor AttachmentCancellationClient: APIClient {
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
