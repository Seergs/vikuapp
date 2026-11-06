import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct TaskBulkCompletionTests {
    @Test(arguments: [false, true], [false, true])
    func `sets only done in one request on the selected API`(usesV2: Bool, isDone: Bool) async throws {
        let client = try BulkCompletionFixtureClient(body: fixture(isDone: isDone))
        let repository = makeRepository(client: client, usesV2: usesV2)

        let tasks = try await repository.setCompletion(taskIDs: [1, 2, 1], isDone: isDone)

        let requests = await client.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.path == "/api/\(usesV2 ? "v2" : "v1")/tasks/bulk")
        #expect(request.method == (usesV2 ? .put : .post))
        #expect(request.queryItems.isEmpty)
        let requestData = try #require(request.body)
        let body = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        #expect(Set(body.keys) == ["task_ids", "fields", "values"])
        #expect(body["task_ids"] as? [Int] == [1, 2])
        #expect(body["fields"] as? [String] == ["done"])
        let values = try #require(body["values"] as? [String: Any])
        #expect(Set(values.keys) == ["done"])
        #expect(values["done"] as? Bool == isDone)
        #expect(tasks.allSatisfy { $0.isDone == isDone })
    }

    @Test func `maps full server task data for later synchronization`() async throws {
        let client = try BulkCompletionFixtureClient(body: fixture())
        let tasks = try await makeRepository(client: client).setCompletion(taskIDs: [1, 2], isDone: true)

        #expect(tasks.map(\.id) == [1, 2])
        #expect(tasks[0].title == "Buy coffee")
        #expect(tasks[0].description == "Whole beans, not ground")
        #expect(tasks[0].projectID == 4)
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].dueDate == ISO8601DateFormatter().date(from: "2026-08-30T00:00:00Z"))
        #expect(tasks[0].labels.map(\.id) == [10])
        #expect(tasks[0].dependsOn.map(\.id) == [3])
        #expect(tasks[0].reminders.count == 1)
        #expect(tasks[0].updated == ISO8601DateFormatter().date(from: "2026-11-06T16:00:00Z"))
        #expect(tasks[1].dueDate == nil)
    }

    @Test func `empty selections perform no request or capability lookup`() async throws {
        let client = try BulkCompletionFixtureClient(body: fixture())
        let capability = BulkCompletionCapabilityProvider(usesV2: true)
        let repository = VikunjaTaskBulkCompletionRepository(client: client, capabilityProvider: capability)

        #expect(try await repository.setCompletion(taskIDs: [], isDone: true).isEmpty)
        #expect(await client.requests.isEmpty)
        #expect(await capability.calls == 0)
    }

    @Test(arguments: [false, true])
    func `unsynced or invalid IDs reject the entire batch before any request`(usesV2: Bool) async throws {
        for invalidID: EntityID in [.local(UUID()), .remote(0), .remote(-1)] {
            let client = try BulkCompletionFixtureClient(body: fixture())
            let repository = makeRepository(client: client, usesV2: usesV2)

            await #expect(throws: VikunjaError.notFound) {
                try await repository.setCompletion(taskIDs: [1, invalidID], isDone: true)
            }
            #expect(await client.requests.isEmpty)
        }
    }

    @Test(arguments: [false, true], [
        VikunjaError.unauthorized,
        .server(message: "Permission denied", statusCode: 403),
        .server(message: "Invalid bulk payload", statusCode: 400),
        .notFound,
        .offline,
        .timeout,
        .server(message: "Server unavailable", statusCode: 503),
    ])
    func `forwards errors without a legacy or per-task fallback`(usesV2: Bool, error: VikunjaError) async throws {
        let client = try BulkCompletionFixtureClient(body: fixture(), error: error)
        let repository = makeRepository(client: client, usesV2: usesV2)

        await #expect(throws: error) {
            try await repository.setCompletion(taskIDs: [1, 2], isDone: false)
        }
        #expect(await client.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func `cancellation is propagated without fallback`(usesV2: Bool) async throws {
        let client = try BulkCompletionFixtureClient(body: fixture(), error: CancellationError())
        let repository = makeRepository(client: client, usesV2: usesV2)

        await #expect(throws: CancellationError.self) {
            try await repository.setCompletion(taskIDs: [1, 2], isDone: true)
        }
        #expect(await client.requests.count == 1)
    }

    @Test(arguments: [[1], [1, 1], [1, 3], [1, 2, 3], []])
    func `incomplete duplicate or unrelated responses do not acknowledge the batch`(responseIDs: [Int]) async throws {
        var response = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        let original = try #require(response["tasks"] as? [[String: Any]])
        response["tasks"] = responseIDs.map { id in
            var task = original[0]
            task["id"] = id
            return task
        }
        let client = try BulkCompletionFixtureClient(body: JSONSerialization.data(withJSONObject: response))
        let repository = makeRepository(client: client)

        await #expect(throws: VikunjaError.self) {
            try await repository.setCompletion(taskIDs: [1, 2], isDone: true)
        }
        #expect(await client.requests.count == 1)
    }

    @Test func `task response order is not assumed to match request order`() async throws {
        let client = try BulkCompletionFixtureClient(body: fixture())
        let tasks = try await makeRepository(client: client).setCompletion(taskIDs: [2, 1], isDone: true)
        #expect(Set(tasks.map(\.id)) == [1, 2])
    }

    @Test func `returns the servers completion state without replacing it with the request`() async throws {
        let client = try BulkCompletionFixtureClient(body: fixture())
        let tasks = try await makeRepository(client: client).setCompletion(taskIDs: [1, 2], isDone: false)
        #expect(tasks.map(\.isDone) == [true, true])
    }

    @Test func `tasks from different projects remain in one request`() async throws {
        var response = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var tasks = try #require(response["tasks"] as? [[String: Any]])
        tasks[1]["project_id"] = 9
        response["tasks"] = tasks
        let client = try BulkCompletionFixtureClient(body: JSONSerialization.data(withJSONObject: response))

        let updated = try await makeRepository(client: client).setCompletion(taskIDs: [1, 2], isDone: true)

        #expect(updated.map(\.projectID) == [4, 9])
        #expect(await client.requests.count == 1)
    }

    @Test(arguments: ["missing", "null", "array", "malformed"])
    func `invalid response envelopes fail rather than returning an empty success`(shape: String) async throws {
        var response = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        let body: Data
        switch shape {
        case "null":
            response["tasks"] = NSNull()
            body = try JSONSerialization.data(withJSONObject: response)
        case "array":
            body = try JSONSerialization.data(withJSONObject: #require(response["tasks"]))
        case "malformed":
            body = Data("{".utf8)
        default:
            response.removeValue(forKey: "tasks")
            body = try JSONSerialization.data(withJSONObject: response)
        }
        let client = BulkCompletionFixtureClient(body: body)
        await #expect(throws: DecodingError.self) {
            try await makeRepository(client: client).setCompletion(taskIDs: [1, 2], isDone: true)
        }
    }

    private func fixture(isDone: Bool = true) throws -> Data {
        let data = try Data(contentsOf: #require(
            Bundle.module.url(forResource: "task-bulk-completion", withExtension: "json"),
        ))
        guard !isDone else { return data }
        var response = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try #require(response["tasks"] as? [[String: Any]])
        response["tasks"] = tasks.map { task in
            var task = task
            task["done"] = false
            task["done_at"] = "0001-01-01T00:00:00Z"
            return task
        }
        response["values"] = ["done": false]
        return try JSONSerialization.data(withJSONObject: response)
    }

    private func makeRepository(
        client: BulkCompletionFixtureClient,
        usesV2: Bool = false,
    ) -> VikunjaTaskBulkCompletionRepository {
        VikunjaTaskBulkCompletionRepository(
            client: client, capabilityProvider: BulkCompletionCapabilityProvider(usesV2: usesV2),
        )
    }
}

private actor BulkCompletionCapabilityProvider: CapabilityProvider {
    let usesV2: Bool
    private(set) var calls = 0

    init(usesV2: Bool) {
        self.usesV2 = usesV2
    }

    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "2.8.0", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        calls += 1
        return feature == .apiV2 && usesV2
    }
}

private actor BulkCompletionFixtureClient: APIClient {
    let body: Data
    let error: (any Error)?
    private(set) var requests: [Endpoint] = []

    init(body: Data, error: (any Error)? = nil) {
        self.body = body
        self.error = error
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        requests.append(endpoint)
        if let error {
            throw error
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: body)
    }

    func send(_ endpoint: Endpoint) async throws {
        requests.append(endpoint)
        throw VikunjaError.notFound
    }

    func data(_ endpoint: Endpoint) async throws -> Data {
        requests.append(endpoint)
        throw VikunjaError.notFound
    }

    func sendWithResponse<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
    ) async throws -> (Response, HTTPURLResponse) {
        requests.append(endpoint)
        throw VikunjaError.notFound
    }
}
