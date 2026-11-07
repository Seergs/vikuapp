import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// Keep HTTP tests inside the existing serialized suite: MockURLProtocol shares state.
extension URLSessionAPIClientTests {
    @Test(arguments: [false, true])
    func `comment snapshot downloads all pages before reporting coverage`(v2: Bool) async throws {
        let fixture = try commentDownloadFixture()
        let firstPage = try commentPageBody(items: [fixture[0]], page: 1, v2: v2)
        let secondPage = try commentPageBody(items: [fixture[1]], page: 2, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            MockURLProtocol.ScriptedResponse(
                statusCode: 200, body: firstPage, headers: ["x-pagination-total-pages": "2"],
            ),
            MockURLProtocol.ScriptedResponse(statusCode: 200, body: secondPage),
        ])
        let repository = try commentDownloadRepository(session: session, v2: v2)
        let snapshot = try await repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(snapshot.comments.map(\.id) == [.remote(1), .remote(2)])
        #expect(snapshot.lastSuccessfulDownloadAt != nil)
        let requests = await capture.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path == "/api/\(v2 ? "v2" : "v1")/tasks/5/comments")
        let url = try #require(requests.last?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "page" }?.value == "2")
    }

    @Test(arguments: [false, true])
    func `later comment page failure does not return a partially downloaded snapshot`(v2: Bool) async throws {
        let fixture = try commentDownloadFixture()
        let firstPage = try commentPageBody(items: [fixture[0]], page: 1, v2: v2)
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            MockURLProtocol.ScriptedResponse(
                statusCode: 200, body: firstPage, headers: ["x-pagination-total-pages": "2"],
            ),
            MockURLProtocol.ScriptedResponse(statusCode: 403, body: "Access denied"),
        ])
        let repository = try commentDownloadRepository(session: session, v2: v2)
        await #expect(throws: (any Error).self) {
            try await repository.fetchCommentSnapshot(taskID: .remote(5))
        }
        #expect(await capture.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func `successful empty comment response still reports downloaded coverage`(v2: Bool) async throws {
        let body = v2 ? #"{"items":null,"total":0,"page":1,"per_page":50,"total_pages":0}"# : "[]"
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let repository = try commentDownloadRepository(session: session, v2: v2)
        let snapshot = try await repository.fetchCommentSnapshot(taskID: .remote(5))
        #expect(snapshot.comments.isEmpty)
        #expect(snapshot.lastSuccessfulDownloadAt != nil)
        #expect(await capture.requests.count == 1)
    }

    private func commentDownloadFixture() throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "comments", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    private func commentPageBody(items: [[String: Any]], page: Int, v2: Bool) throws -> String {
        let value: Any = v2
            ? ["items": items, "total": 2, "page": page, "per_page": 1, "total_pages": 2]
            : items
        return try #require(String(data: JSONSerialization.data(withJSONObject: value), encoding: .utf8))
    }

    private func commentDownloadRepository(session: URLSession, v2: Bool) throws -> any TaskCommentRepositoryProtocol {
        let client = try URLSessionAPIClient(
            baseURL: #require(URL(string: "https://vikunja.example.com")), session: session,
        )
        return v2 ? VikunjaTaskCommentRepositoryV2(client: client) : VikunjaTaskCommentRepository(client: client)
    }
}
