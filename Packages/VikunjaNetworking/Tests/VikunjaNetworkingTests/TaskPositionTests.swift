import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

private actor PositionFixtureClient: APIClient {
    let response: Data
    var failure: VikunjaError?
    private(set) var endpoints: [Endpoint] = []

    init(response: Data, failure: VikunjaError? = nil) {
        self.response = response
        self.failure = failure
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        endpoints.append(endpoint)
        if let failure {
            throw failure
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func send(_ endpoint: Endpoint) async throws {
        throw VikunjaError.notFound
    }

    func data(_ endpoint: Endpoint) async throws -> Data {
        throw VikunjaError.notFound
    }

    func sendWithResponse<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws
        -> (Response, HTTPURLResponse) {
        throw VikunjaError.notFound
    }
}

struct TaskPositionTests {
    /// Complete TaskPosition response contract from the server's task_position.go
    /// and api/v2/task_position.go: all three resource fields, without a task envelope.
    private func fixture() throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: "task-view-position", withExtension: "json")))
    }

    @Test
    func `position PUT sends only view and position and accepts server renormalization`() async throws {
        let client = try PositionFixtureClient(response: fixture())
        let result = try await VikunjaBucketRepository(client: client).setTaskPosition(
            taskID: 3,
            viewID: 12,
            position: 0.001,
        )
        #expect(result == TaskViewPosition(taskID: 3, viewID: 12, position: 1_431_655_765.3333333))
        let request = try #require(await client.endpoints.first)
        #expect(request.path == "/api/v2/tasks/3/position")
        #expect(request.method == .put)
        #expect(!request.allowsAutomaticRetry)
        let data = try #require(request.body)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Double])
        #expect(body == ["project_view_id": 12, "position": 0.001])
    }

    @Test(arguments: ["task_id", "project_view_id", "position"])
    func `mismatched identities and sentinel returned positions are rejected`(field: String) async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        object[field] = 0
        let client = try PositionFixtureClient(response: JSONSerialization.data(withJSONObject: object))
        await #expect(throws: VikunjaError.self) {
            try await VikunjaBucketRepository(client: client).setTaskPosition(taskID: 3, viewID: 12, position: 50)
        }
    }

    @Test
    func `transport errors propagate without falling back to task replacement`() async throws {
        let client = try PositionFixtureClient(response: fixture(), failure: .offline)
        await #expect(throws: VikunjaError.offline) {
            try await VikunjaBucketRepository(client: client).setTaskPosition(taskID: 3, viewID: 12, position: 50)
        }
        #expect(await client.endpoints.count == 1)
    }
}
