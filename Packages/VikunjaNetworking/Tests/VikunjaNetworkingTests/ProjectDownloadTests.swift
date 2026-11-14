import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// HTTP fixtures share MockURLProtocol state, so these belong to the serialized suite.
extension URLSessionAPIClientTests {
    @Test(arguments: [false, true], [20, 50])
    func `project catalog includes every page beyond fifty projects`(v2: Bool, pageSize: Int) async throws {
        let templates = try projectDownloadFixture()
        let items = (1 ... 53).map { id in
            var item = templates[(id - 1) % templates.count]
            item["id"] = id
            item["parent_project_id"] = id == 1 ? 53 : 0
            return item
        }
        let responses = try stride(from: 0, to: items.count, by: pageSize).enumerated().map { index, offset in
            try MockURLProtocol.ScriptedResponse(
                statusCode: 200,
                body: projectPageBody(
                    items: Array(items[offset ..< min(offset + pageSize, items.count)]),
                    page: index + 1, total: items.count, perPage: pageSize, v2: v2,
                ),
                headers: ["x-pagination-total-pages": String((items.count + pageSize - 1) / pageSize)],
            )
        }
        let (session, capture) = MockURLProtocol.makeSession(responses: responses)
        let projects = try await projectDownloadRepository(session: session, v2: v2).fetchProjects()

        #expect(projects.map(\.id) == (1 ... 53).map { .remote($0) })
        #expect(projects.first?.title == templates.first?["title"] as? String)
        #expect(projects.first?.hexColor == templates.first?["hex_color"] as? String)
        #expect(projects.first?.parentProjectID == .remote(53))
        #expect(projects.last?.parentProjectID == nil)
        let requests = await capture.requests
        #expect(requests.count == responses.count)
        for (index, request) in requests.enumerated() {
            #expect(request.url?.path == "/api/\(v2 ? "v2" : "v1")/projects")
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(query == [URLQueryItem(name: "page", value: String(index + 1))])
        }
    }

    @Test(arguments: [false, true])
    func `later project pages preserve saved filters and favorites`(v2: Bool) async throws {
        let fixture = try projectDownloadFixture()
        var favorites = fixture[0]
        favorites["id"] = -1
        var filter = fixture[0]
        filter["id"] = -8
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: projectPageBody(items: [fixture[2], favorites, filter], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: projectPageBody(items: [fixture[1], favorites, filter], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        let projects = try await projectDownloadRepository(session: session, v2: v2).fetchProjects()
        #expect(projects.map(\.id) == [.remote(12), .remote(-1), .remote(-8), .remote(6)])
        #expect(projects[0].parentProjectID == projects[3].id)
        #expect(projects[1].kind == .favorites)
        #expect(projects[2].kind == .savedFilter)
        #expect(projects[2].savedFilterID == 7)
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true], [0, 1])
    func `virtual projects are not counted in single page totals`(v2: Bool, realCount: Int) async throws {
        let fixture = try projectDownloadFixture()
        var favorites = fixture[0]
        favorites["id"] = -1
        var filter = fixture[0]
        filter["id"] = -8
        let items = Array(fixture.prefix(realCount)) + [favorites, filter]
        let body = try projectPageBody(items: items, page: 1, total: realCount, perPage: 50, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": String(realCount)],
        )
        let projects = try await projectDownloadRepository(session: session, v2: v2).fetchProjects()
        #expect(projects.count == realCount + 2)
        #expect(projects.suffix(2).map(\.kind) == [.favorites, .savedFilter])
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `virtual entries cannot hide a missing page of real projects`(v2: Bool) async throws {
        let fixture = try projectDownloadFixture()
        var favorites = fixture[0]
        favorites["id"] = -1
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: projectPageBody(items: [fixture[0], favorites], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: projectPageBody(items: [favorites], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        await #expect(throws: VikunjaError.self) {
            try await projectDownloadRepository(session: session, v2: v2).fetchProjects()
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `single project page is returned without extra requests`(v2: Bool) async throws {
        let fixture = try projectDownloadFixture()
        let body = try projectPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: v2)
        // Some v1 responses omit pagination headers for a single-page result.
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let projects = try await projectDownloadRepository(session: session, v2: v2).fetchProjects()
        #expect(projects.count == fixture.count)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `empty project catalog makes only one request`(v2: Bool) async throws {
        let body = v2 ? #"{"items":null,"total":0,"page":1,"per_page":50,"total_pages":0}"# : "[]"
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": "0"],
        )
        #expect(try await projectDownloadRepository(session: session, v2: v2).fetchProjects().isEmpty)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true], [200, 403])
    func `later project page failure never returns a partial catalog`(v2: Bool, status: Int) async throws {
        let items = try projectDownloadFixture()
        let first = try projectPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: status, body: "Invalid response"),
        ])
        await #expect(throws: (any Error).self) {
            try await projectDownloadRepository(session: session, v2: v2).fetchProjects()
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `unexpected empty project page is an incomplete download`(v2: Bool) async throws {
        let items = try projectDownloadFixture()
        let first = try projectPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let second = try projectPageBody(items: [], page: 2, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: 200, body: second),
        ])
        await #expect(throws: VikunjaError.self) {
            try await projectDownloadRepository(session: session, v2: v2).fetchProjects()
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true], [1, 2])
    func `cancelled project download never publishes a catalog`(v2: Bool, cancelAfterPage: Int) async throws {
        let items = try projectDownloadFixture()
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: projectPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: projectPageBody(items: [items[1]], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        let base = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let client = ProjectCancellationClient(base: base, cancelAfterPage: cancelAfterPage)
        let repository: any ProjectRepositoryProtocol = v2
            ? VikunjaProjectRepositoryV2(client: client) : VikunjaProjectRepository(client: client)
        let download = Task { try await repository.fetchProjects() }
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await capture.requests.count == cancelAfterPage)
    }

    @Test(arguments: ["-1", "invalid"])
    func `invalid v1 project pagination is not treated as a complete catalog`(header: String) async throws {
        let fixture = try projectDownloadFixture()
        let body = try projectPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: false)
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": header],
        )
        await #expect(throws: VikunjaError.self) {
            try await projectDownloadRepository(session: session, v2: false).fetchProjects()
        }
    }

    @Test(arguments: ["page", "total", "total_pages", "items"])
    func `inconsistent v2 project pagination is not a complete catalog`(field: String) async throws {
        let items = try projectDownloadFixture()
        var fourth = items[0]
        fourth["id"] = 4
        let first = try projectPageBody(items: Array(items.prefix(2)), page: 1, total: 4, perPage: 2, v2: true)
        let second = try projectPageBody(items: [items[2], fourth], page: 2, total: 4, perPage: 2, v2: true)
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
            try await projectDownloadRepository(session: session, v2: true).fetchProjects()
        }
    }

    private func projectDownloadFixture() throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "projects", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    private func projectPageBody(items: [[String: Any]], page: Int, total: Int, perPage: Int, v2: Bool) throws -> String {
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

    private func projectDownloadRepository(session: URLSession, v2: Bool) throws -> any ProjectRepositoryProtocol {
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        return v2 ? VikunjaProjectRepositoryV2(client: client) : VikunjaProjectRepository(client: client)
    }
}

/// Cancel deterministically after a decoded response, including the final page.
private actor ProjectCancellationClient: APIClient {
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
