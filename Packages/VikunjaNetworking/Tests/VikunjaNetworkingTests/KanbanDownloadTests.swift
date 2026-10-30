import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

private actor KanbanFixtureClient: APIClient {
    let views: Data
    let pages: [Data]
    private(set) var bucketRequests = 0
    init(views: Data, pages: [Data]) {
        self.views = views; self.pages = pages
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        let data: Data
        if endpoint.path.hasSuffix("/views") {
            data = views
        } else {
            let index = bucketRequests
            bucketRequests += 1
            guard index < pages.count else { throw VikunjaError.offline }
            data = pages[index]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }

    func send(_ endpoint: Endpoint) async throws {
        throw VikunjaError.notFound
    }

    func data(_ endpoint: Endpoint) async throws -> Data {
        throw VikunjaError.notFound
    }

    func sendWithResponse<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
    ) async throws -> (Response, HTTPURLResponse) {
        throw VikunjaError.notFound
    }
}

struct KanbanDownloadTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json")))
    }

    @Test func `metadata and all pages are downloaded`() async throws {
        let raw = try fixture("buckets-with-tasks")
        var object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var buckets = try #require(object["items"] as? [[String: Any]])
        buckets[0]["count"] = 2
        object["items"] = buckets
        let first = try JSONSerialization.data(withJSONObject: object)
        var tasks = try #require(buckets[0]["tasks"] as? [[String: Any]])
        tasks[0]["id"] = 101
        buckets[0]["tasks"] = tasks
        buckets[1]["tasks"] = []
        object["items"] = buckets
        let second = try JSONSerialization.data(withJSONObject: object)
        let client = try KanbanFixtureClient(views: fixture("project-views"), pages: [first, second])
        let board = try await VikunjaBucketRepository(client: client).downloadBoard(projectID: 6, viewID: nil)
        #expect(board.viewID == 11)
        #expect(board.mode == "manual")
        #expect(board.defaultBucketID == 20)
        #expect(board.doneBucketID == 22)
        #expect(board.filterQuery.isEmpty)
        #expect(board.buckets[0].tasks.map(\.id) == [.remote(100), .remote(101)])
        #expect(await client.bucketRequests == 2)
    }

    @Test func `later page failure and truncated pages are not successful downloads`() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture("buckets-with-tasks")) as? [String: Any])
        var buckets = try #require(object["items"] as? [[String: Any]])
        buckets[0]["count"] = 2
        object["items"] = buckets
        let first = try JSONSerialization.data(withJSONObject: object)
        let failed = try KanbanFixtureClient(views: fixture("project-views"), pages: [first])
        await #expect(throws: VikunjaError.offline) {
            try await VikunjaBucketRepository(client: failed).downloadBoard(projectID: 6, viewID: nil)
        }
        buckets[0]["tasks"] = []
        buckets[1]["tasks"] = []
        object["items"] = buckets
        let truncated = try KanbanFixtureClient(
            views: fixture("project-views"),
            pages: [first, JSONSerialization.data(withJSONObject: object)],
        )
        await #expect(throws: VikunjaError.self) {
            try await VikunjaBucketRepository(client: truncated).downloadBoard(projectID: 6, viewID: nil)
        }
    }

    @Test func `filtered view metadata disables local rule assumptions`() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture("project-views")) as? [String: Any])
        var views = try #require(object["items"] as? [[String: Any]])
        views[1]["filter"] = ["filter": "done = false"]
        views[1]["bucket_configuration_mode"] = "filter"
        object["items"] = views
        let client = try KanbanFixtureClient(
            views: JSONSerialization.data(withJSONObject: object),
            pages: [fixture("buckets-with-tasks")],
        )
        let board = try await VikunjaBucketRepository(client: client).downloadBoard(projectID: 6, viewID: nil)
        #expect(board.mode == "filter")
        #expect(board.filterQuery.contains("done = false"))
    }

    @Test func `missing pinned view does not switch boards`() async throws {
        let client = try KanbanFixtureClient(views: fixture("project-views"), pages: [])
        await #expect(throws: VikunjaError.notFound) {
            try await VikunjaBucketRepository(client: client).downloadBoard(projectID: 6, viewID: 99)
        }
        #expect(await client.bucketRequests == 0)
    }
}
