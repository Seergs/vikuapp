import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// HTTP fixtures share MockURLProtocol state, so these belong to the serialized suite.
extension URLSessionAPIClientTests {
    @Test(arguments: [false, true], [20, 50])
    func `project task list includes every page beyond fifty tasks`(v2: Bool, pageSize: Int) async throws {
        let templates = try projectTaskFixture()
        let items = (1 ... 53).map { id in
            var item = templates[(id - 1) % templates.count]
            item["id"] = id
            return item
        }
        let responses = try stride(from: 0, to: items.count, by: pageSize).enumerated().map { index, offset in
            try MockURLProtocol.ScriptedResponse(
                statusCode: 200,
                body: projectTaskPageBody(
                    items: Array(items[offset ..< min(offset + pageSize, items.count)]),
                    page: index + 1, total: items.count, perPage: pageSize, v2: v2,
                ),
                headers: ["x-pagination-total-pages": String((items.count + pageSize - 1) / pageSize)],
            )
        }
        let (session, capture) = MockURLProtocol.makeSession(responses: responses)
        let tasks = try await projectTaskRepository(session: session, v2: v2).fetchTasks(projectID: .remote(4))

        #expect(tasks.map(\.id) == (1 ... 53).map { .remote($0) })
        #expect(tasks.first?.title == templates.first?["title"] as? String)
        #expect(tasks.first?.labels.map(\.id) == [.remote(10)])
        #expect(tasks.first?.priority.rawValue == 3)
        #expect(tasks.allSatisfy { $0.projectID == .remote(4) })
        let requests = await capture.requests
        #expect(requests.count == responses.count)
        for (index, request) in requests.enumerated() {
            #expect(request.url?.path == "/api/\(v2 ? "v2" : "v1")/projects/4/tasks")
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(query == [URLQueryItem(name: "page", value: String(index + 1))])
        }
    }

    @Test(arguments: [false, true])
    func `single project task page is returned without extra requests`(v2: Bool) async throws {
        let fixture = try projectTaskFixture()
        let body = try projectTaskPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: v2)
        // Some v1 responses omit pagination headers for a single-page result.
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let tasks = try await projectTaskRepository(session: session, v2: v2).fetchTasks(projectID: .remote(4))
        #expect(tasks.count == fixture.count)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `empty project task list makes only one request`(v2: Bool) async throws {
        let body = v2 ? #"{"items":null,"total":0,"page":1,"per_page":50,"total_pages":0}"# : "[]"
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": "0"],
        )
        #expect(try await projectTaskRepository(session: session, v2: v2).fetchTasks(projectID: .remote(4)).isEmpty)
        #expect(await capture.requests.count == 1)
    }

    @Test(arguments: [false, true], [200, 403])
    func `later project task page failure never returns a partial catalog`(v2: Bool, status: Int) async throws {
        let items = try projectTaskFixture()
        let first = try projectTaskPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: status, body: "Invalid response"),
        ])
        await #expect(throws: (any Error).self) {
            try await projectTaskRepository(session: session, v2: v2).fetchTasks(projectID: .remote(4))
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `unexpected empty project task page is an incomplete download`(v2: Bool) async throws {
        let items = try projectTaskFixture()
        let first = try projectTaskPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2)
        let second = try projectTaskPageBody(items: [], page: 2, total: 2, perPage: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            .init(statusCode: 200, body: first, headers: ["x-pagination-total-pages": "2"]),
            .init(statusCode: 200, body: second),
        ])
        await #expect(throws: VikunjaError.self) {
            try await projectTaskRepository(session: session, v2: v2).fetchTasks(projectID: .remote(4))
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true], [1, 2])
    func `cancelled project task download never publishes a catalog`(v2: Bool, cancelAfterPage: Int) async throws {
        let items = try projectTaskFixture()
        let (session, capture) = try MockURLProtocol.makeSession(responses: [
            .init(
                statusCode: 200,
                body: projectTaskPageBody(items: [items[0]], page: 1, total: 2, perPage: 1, v2: v2),
                headers: ["x-pagination-total-pages": "2"],
            ),
            .init(
                statusCode: 200,
                body: projectTaskPageBody(items: [items[1]], page: 2, total: 2, perPage: 1, v2: v2),
            ),
        ])
        let base = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let client = PaginationCancellationClient(base: base, cancelAfterPage: cancelAfterPage)
        let repository: any TaskRepositoryProtocol = v2
            ? VikunjaTaskRepositoryV2(client: client) : VikunjaTaskRepository(client: client)
        let download = Task { try await repository.fetchTasks(projectID: .remote(4)) }
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await capture.requests.count == cancelAfterPage)
    }

    @Test(arguments: ["-1", "invalid"])
    func `invalid v1 project task pagination is not treated as a complete catalog`(header: String) async throws {
        let fixture = try projectTaskFixture()
        let body = try projectTaskPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: false)
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200, body: body, headers: ["x-pagination-total-pages": header],
        )
        await #expect(throws: VikunjaError.self) {
            try await projectTaskRepository(session: session, v2: false).fetchTasks(projectID: .remote(4))
        }
    }

    @Test(arguments: ["page", "total", "total_pages", "items"])
    func `inconsistent v2 project task pagination is not a complete catalog`(field: String) async throws {
        let items = try projectTaskFixture()
        var fourth = items[0]
        fourth["id"] = 4
        let first = try projectTaskPageBody(items: Array(items.prefix(2)), page: 1, total: 4, perPage: 2, v2: true)
        let second = try projectTaskPageBody(items: [items[2], fourth], page: 2, total: 4, perPage: 2, v2: true)
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
            try await projectTaskRepository(session: session, v2: true).fetchTasks(projectID: .remote(4))
        }
    }

    @Test(arguments: [false, true])
    func `unsynced project task list is empty without a request`(v2: Bool) async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "[]")
        let repository = try projectTaskRepository(session: session, v2: v2)
        #expect(try await repository.fetchTasks(projectID: .local(UUID())).isEmpty)
        #expect(await capture.requests.isEmpty)
    }

    @Test(arguments: [false, true], [-1, -8])
    func `virtual project task download preserves its scope and task owner`(v2: Bool, projectID: Int) async throws {
        let fixture = try projectTaskFixture()
        let body = try projectTaskPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let tasks = try await projectTaskRepository(session: session, v2: v2).fetchTasks(projectID: .remote(projectID))
        #expect(tasks.allSatisfy { $0.projectID == .remote(4) })
        #expect(await capture.requests.first?.url?.path == "/api/\(v2 ? "v2" : "v1")/projects/\(projectID)/tasks")
    }

    @Test(arguments: ["page", "total", "total_pages", "zero_pages"])
    func `invalid v2 project task first page cannot become a complete download`(field: String) async throws {
        let fixture = try projectTaskFixture()
        let page = try projectTaskPageBody(items: fixture, page: 1, total: fixture.count, perPage: 50, v2: true)
        var object = try #require(JSONSerialization.jsonObject(with: Data(page.utf8)) as? [String: Any])
        object[field == "zero_pages" ? "total_pages" : field] = field == "zero_pages" ? 0 : -1
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        await #expect(throws: VikunjaError.self) {
            try await projectTaskRepository(session: session, v2: true).fetchTasks(projectID: .remote(4))
        }
        #expect(await capture.requests.count == 1)
    }

    private func projectTaskFixture() throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "task", withExtension: "json"))
        let template = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (1 ... 3).map { id in
            var item = template
            item["id"] = id
            return item
        }
    }

    private func projectTaskPageBody(items: [[String: Any]], page: Int, total: Int, perPage: Int, v2: Bool) throws -> String {
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

    private func projectTaskRepository(session: URLSession, v2: Bool) throws -> any TaskRepositoryProtocol {
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        return v2 ? VikunjaTaskRepositoryV2(client: client) : VikunjaTaskRepository(client: client)
    }
}
