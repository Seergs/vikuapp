import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// HTTP fixtures share MockURLProtocol state, so these belong to the serialized suite.
extension URLSessionAPIClientTests {
    @Test(arguments: [false, true], [20, 50])
    func `remote search includes every page beyond fifty matching tasks`(v2: Bool, pageSize: Int) async throws {
        let templates = try remoteSearchFixture()
        let items = (1 ... 53).map { id in
            var item = templates[(id - 1) % templates.count]
            item["id"] = id
            item["project_id"] = id.isMultiple(of: 2) ? 9 : 4
            return item
        }
        let responses = try stride(from: 0, to: items.count, by: pageSize).enumerated().map { index, offset in
            try MockURLProtocol.ScriptedResponse(
                statusCode: 200,
                body: remoteSearchPageBody(
                    items: Array(items[offset ..< min(offset + pageSize, items.count)]),
                    page: index + 1, total: items.count, perPage: pageSize, v2: v2,
                ),
                headers: ["x-pagination-total-pages": String((items.count + pageSize - 1) / pageSize)],
            )
        }
        let (session, capture) = MockURLProtocol.makeSession(responses: responses)
        let tasks = try await remoteSearchRepository(session: session, v2: v2).searchTasks(query: remoteSearchQuery)

        #expect(tasks.map(\.id) == (1 ... 53).map { .remote($0) })
        #expect(tasks.first?.title == templates.first?["title"] as? String)
        #expect(tasks.first?.description == templates.first?["description"] as? String)
        #expect(tasks.first?.labels.map(\.id) == [.remote(10)])
        #expect(tasks.first?.priority.rawValue == 3)
        #expect(tasks.map(\.projectID) == (1 ... 53).map { .remote($0.isMultiple(of: 2) ? 9 : 4) })
        let requests = await capture.requests
        #expect(requests.count == responses.count)
        for (index, request) in requests.enumerated() {
            #expect(request.url?.path == "/api/\(v2 ? "v2" : "v1")/tasks")
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(query == [
                URLQueryItem(name: v2 ? "q" : "s", value: remoteSearchQuery),
                URLQueryItem(name: "page", value: String(index + 1)),
            ])
        }
    }

    @Test(arguments: [false, true])
    func `single remote search page is returned without extra requests`(v2: Bool) async throws {
        let fixture = try remoteSearchFixture()
        let body = try remoteSearchPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: v2)
        // Some v1 responses omit pagination headers for a single-page result.
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let tasks = try await remoteSearchRepository(session: session, v2: v2).searchTasks(query: remoteSearchQuery)
        #expect(tasks.count == fixture.count)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `empty remote search result makes only one request`(v2: Bool) async throws {
        let body = v2 ? #"{"items":null,"total":0,"page":1,"per_page":50,"total_pages":0}"# : "[]"
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": "0"],
        )
        let repository = try remoteSearchRepository(session: session, v2: v2)
        #expect(try await repository.searchTasks(query: remoteSearchQuery).isEmpty)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true], [200, 403])
    func `later remote search page failure never returns a partial catalog`(v2: Bool, status: Int) async throws {
        let items = try remoteSearchFixture()
        let first = try remoteSearchPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: status, body: "Invalid response"),
        ])
        await #expect(throws: (any Error).self) {
            try await remoteSearchRepository(session: session, v2: v2).searchTasks(query: remoteSearchQuery)
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `unexpected empty remote search page is an incomplete download`(v2: Bool) async throws {
        let items = try remoteSearchFixture()
        let first = try remoteSearchPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let second = try remoteSearchPageBody(items: [], page: 2, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: 200, body: second),
        ])
        await #expect(throws: VikunjaError.self) {
            try await remoteSearchRepository(session: session, v2: v2).searchTasks(query: remoteSearchQuery)
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true], [1, 2])
    func `cancelled remote search never publishes a catalog`(v2: Bool, cancelAfterPage: Int) async throws {
        let items = try remoteSearchFixture()
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: remoteSearchPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: remoteSearchPageBody(items: [items[1]], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        let base = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let client = SearchCancellationClient(base: base, cancelAfterPage: cancelAfterPage)
        let repository: any TaskRepositoryProtocol = v2
            ? VikunjaTaskRepositoryV2(client: client) : VikunjaTaskRepository(client: client)
        let download = Task { try await repository.searchTasks(query: remoteSearchQuery) }
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await capture.requests.count == cancelAfterPage)
    }

    @Test(arguments: ["-1", "invalid"])
    func `invalid v1 remote search pagination is not treated as a complete catalog`(header: String) async throws {
        let fixture = try remoteSearchFixture()
        let body = try remoteSearchPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: false)
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": header],
        )
        await #expect(throws: VikunjaError.self) {
            try await remoteSearchRepository(session: session, v2: false).searchTasks(query: remoteSearchQuery)
        }
    }

    @Test(arguments: ["page", "total", "total_pages", "items"])
    func `inconsistent v2 remote search pagination is not a complete catalog`(field: String) async throws {
        let items = try remoteSearchFixture()
        var fourth = items[0]
        fourth["id"] = 4
        let first = try remoteSearchPageBody(items: Array(items.prefix(2)), page: 1, total: 4, perPage: 2, v2: true)
        let second = try remoteSearchPageBody(items: [items[2], fourth], page: 2, total: 4, perPage: 2, v2: true)
        var object = try #require(JSONSerialization.jsonObject(with: Data(second.utf8)) as? [String: Any])
        if field == "items" {
            object[field] = [items[2]]
        } else {
            object[field] = 1
        }
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        let (session, _) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first),
            .init(statusCode: 200, body: body),
        ])
        await #expect(throws: VikunjaError.self) {
            try await remoteSearchRepository(session: session, v2: true).searchTasks(query: remoteSearchQuery)
        }
    }

    private var remoteSearchQuery: String {
        #"café & "a+b" /? +Project @label"#
    }

    private func remoteSearchFixture() throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "task", withExtension: "json"))
        let template = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (1 ... 3).map { id in
            var item = template
            item["id"] = id
            return item
        }
    }

    private func remoteSearchPageBody(items: [[String: Any]], page: Int, total: Int, perPage: Int, v2: Bool) throws -> String {
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

    private func remoteSearchRepository(session: URLSession, v2: Bool) throws -> any TaskRepositoryProtocol {
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        return v2 ? VikunjaTaskRepositoryV2(client: client) : VikunjaTaskRepository(client: client)
    }
}

/// Cancel deterministically after a decoded response, including the final page.
private actor SearchCancellationClient: APIClient {
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
