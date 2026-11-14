import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// HTTP fixtures share MockURLProtocol state, so these belong to the serialized suite.
extension URLSessionAPIClientTests {
    @Test(arguments: [false, true], [20, 50])
    func `comment catalog includes every page beyond fifty comments`(v2: Bool, pageSize: Int) async throws {
        let templates = try paginatedCommentFixture()
        let items = (1 ... 53).map { id in
            var item = templates[(id - 1) % templates.count]
            item["id"] = id
            return item
        }
        let responses = try stride(from: 0, to: items.count, by: pageSize).enumerated().map { index, offset in
            try MockURLProtocol.ScriptedResponse(
                statusCode: 200,
                body: paginatedCommentPageBody(
                    items: Array(items[offset ..< min(offset + pageSize, items.count)]),
                    page: index + 1, total: items.count, perPage: pageSize, v2: v2,
                ),
                headers: ["x-pagination-total-pages": String((items.count + pageSize - 1) / pageSize)],
            )
        }
        let (session, capture) = MockURLProtocol.makeSession(responses: responses)
        let repository = try paginatedCommentRepository(session: session, v2: v2)
        let snapshot = try await repository.fetchCommentSnapshot(taskID: .remote(5))
        let comments = snapshot.comments
        #expect(snapshot.lastSuccessfulDownloadAt != nil)

        #expect(comments.map(\.id) == (1 ... 53).map { .remote($0) })
        #expect(comments.first?.comment == templates.first?["comment"] as? String)
        #expect(comments.first?.author == User(id: 7, username: "alex", name: "Alex"))
        let requests = await capture.requests
        #expect(requests.count == responses.count)
        for (index, request) in requests.enumerated() {
            #expect(request.url?.path == "/api/\(v2 ? "v2" : "v1")/tasks/5/comments")
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(query == [URLQueryItem(name: "page", value: String(index + 1))])
        }
    }

    @Test(arguments: [false, true])
    func `single comment page is returned without extra requests`(v2: Bool) async throws {
        let fixture = try paginatedCommentFixture()
        let body = try paginatedCommentPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: v2)
        // Some v1 responses omit pagination headers for a single-page result.
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let repository = try paginatedCommentRepository(session: session, v2: v2)
        let snapshot = try await repository.fetchCommentSnapshot(taskID: .remote(5))
        let comments = snapshot.comments
        #expect(snapshot.lastSuccessfulDownloadAt != nil)
        #expect(comments.count == fixture.count)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `empty comment catalog makes only one request`(v2: Bool) async throws {
        let body = v2 ? #"{"items":null,"total":0,"page":1,"per_page":50,"total_pages":0}"# : "[]"
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": "0"],
        )
        let repository = try paginatedCommentRepository(session: session, v2: v2)
        #expect(try await repository.fetchComments(taskID: .remote(5)).isEmpty)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true], [200, 403])
    func `later comment page failure never returns a partial catalog`(v2: Bool, status: Int) async throws {
        let items = try paginatedCommentFixture()
        let first = try paginatedCommentPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: status, body: "Invalid response"),
        ])
        await #expect(throws: (any Error).self) {
            try await paginatedCommentRepository(session: session, v2: v2).fetchComments(taskID: .remote(5))
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `unexpected empty comment page is an incomplete download`(v2: Bool) async throws {
        let items = try paginatedCommentFixture()
        let first = try paginatedCommentPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let second = try paginatedCommentPageBody(items: [], page: 2, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: 200, body: second),
        ])
        await #expect(throws: VikunjaError.self) {
            try await paginatedCommentRepository(session: session, v2: v2).fetchComments(taskID: .remote(5))
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true], [1, 2])
    func `cancelled comment download never publishes a catalog`(v2: Bool, cancelAfterPage: Int) async throws {
        let items = try paginatedCommentFixture()
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: paginatedCommentPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: paginatedCommentPageBody(items: [items[1]], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        let base = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let client = PaginationCancellationClient(base: base, cancelAfterPage: cancelAfterPage)
        let repository: any TaskCommentRepositoryProtocol = v2
            ? VikunjaTaskCommentRepositoryV2(client: client) : VikunjaTaskCommentRepository(client: client)
        let download = Task { try await repository.fetchCommentSnapshot(taskID: .remote(5)) }
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await capture.requests.count == cancelAfterPage)
    }

    @Test(arguments: ["-1", "invalid"])
    func `invalid v1 comment pagination is not treated as a complete catalog`(header: String) async throws {
        let fixture = try paginatedCommentFixture()
        let body = try paginatedCommentPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: false)
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": header],
        )
        await #expect(throws: VikunjaError.self) {
            try await paginatedCommentRepository(session: session, v2: false).fetchComments(taskID: .remote(5))
        }
    }

    @Test(arguments: ["page", "total", "total_pages", "items"])
    func `inconsistent v2 comment pagination is not a complete catalog`(field: String) async throws {
        let items = try paginatedCommentFixture()
        var fourth = items[0]
        fourth["id"] = 4
        let first = try paginatedCommentPageBody(items: Array(items.prefix(2)), page: 1, total: 4, perPage: 2, v2: true)
        let second = try paginatedCommentPageBody(items: [items[0], fourth], page: 2, total: 4, perPage: 2, v2: true)
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
            try await paginatedCommentRepository(session: session, v2: true).fetchComments(taskID: .remote(5))
        }
    }

    @Test(arguments: ["page", "total", "total_pages", "zero_pages"])
    func `invalid v2 comment first page cannot become a complete download`(field: String) async throws {
        let fixture = try paginatedCommentFixture()
        let page = try paginatedCommentPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: true)
        var object = try #require(JSONSerialization.jsonObject(with: Data(page.utf8)) as? [String: Any])
        object[field == "zero_pages" ? "total_pages" : field] = field == "zero_pages" ? 0 : -1
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        await #expect(throws: VikunjaError.self) {
            try await paginatedCommentRepository(session: session, v2: true).fetchCommentSnapshot(taskID: .remote(5))
        }
        #expect(await capture.requests.count == 1)
    }

    private func paginatedCommentFixture() throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "comments", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    private func paginatedCommentPageBody(items: [[String: Any]], page: Int, total: Int, perPage: Int, v2: Bool) throws -> String {
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

    private func paginatedCommentRepository(session: URLSession, v2: Bool) throws -> any TaskCommentRepositoryProtocol {
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        return v2 ? VikunjaTaskCommentRepositoryV2(client: client) : VikunjaTaskCommentRepository(client: client)
    }
}
