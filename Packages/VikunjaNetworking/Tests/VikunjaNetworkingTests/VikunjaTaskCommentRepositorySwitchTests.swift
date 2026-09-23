import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct VikunjaTaskCommentRepositorySwitchTests {
    @Test
    func `delegates to v1 when the capability provider does not support apiV2`() async throws {
        let v1 = SpyCommentRepository(label: "v1")
        let v2 = SpyCommentRepository(label: "v2")
        let capabilityProvider = FakeCommentCapabilityProvider(supportsAPIV2: false)
        let repository = VikunjaTaskCommentRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let comments = try await repository.fetchComments(taskID: 1)

        #expect(comments.first?.comment == "v1")
        #expect(v1.fetchCommentsCallCount == 1)
        #expect(v2.fetchCommentsCallCount == 0)
    }

    @Test
    func `delegates to v2 when the capability provider supports apiV2`() async throws {
        let v1 = SpyCommentRepository(label: "v1")
        let v2 = SpyCommentRepository(label: "v2")
        let capabilityProvider = FakeCommentCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskCommentRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        let comments = try await repository.fetchComments(taskID: 1)

        #expect(comments.first?.comment == "v2")
        #expect(v1.fetchCommentsCallCount == 0)
        #expect(v2.fetchCommentsCallCount == 1)
    }

    @Test
    func `resolves the capability independently for every method`() async throws {
        let v1 = SpyCommentRepository(label: "v1")
        let v2 = SpyCommentRepository(label: "v2")
        let capabilityProvider = FakeCommentCapabilityProvider(supportsAPIV2: true)
        let repository = VikunjaTaskCommentRepositorySwitch(v1: v1, v2: v2, capabilityProvider: capabilityProvider)

        _ = try await repository.addComment("hi", toTask: 1)
        _ = try await repository.updateComment(1, text: "hi", onTask: 1)
        try await repository.deleteComment(1, fromTask: 1)

        #expect(v1.addCommentCallCount == 0)
        #expect(v1.updateCommentCallCount == 0)
        #expect(v1.deleteCommentCallCount == 0)
        #expect(v2.addCommentCallCount == 1)
        #expect(v2.updateCommentCallCount == 1)
        #expect(v2.deleteCommentCallCount == 1)
    }
}

private final class SpyCommentRepository: TaskCommentRepositoryProtocol, @unchecked Sendable {
    let label: String
    private(set) var fetchCommentsCallCount = 0
    private(set) var addCommentCallCount = 0
    private(set) var updateCommentCallCount = 0
    private(set) var deleteCommentCallCount = 0

    init(label: String) {
        self.label = label
    }

    private static let author = User(id: 1, username: "sergio")

    func fetchComments(taskID: Int) async throws -> [TaskComment] {
        fetchCommentsCallCount += 1
        return [TaskComment(id: 1, comment: label, author: Self.author, created: .now, updated: .now)]
    }

    func addComment(_ text: String, toTask taskID: Int) async throws -> TaskComment {
        addCommentCallCount += 1
        return TaskComment(id: 1, comment: text, author: Self.author, created: .now, updated: .now)
    }

    func updateComment(_ commentID: Int, text: String, onTask taskID: Int) async throws -> TaskComment {
        updateCommentCallCount += 1
        return TaskComment(id: commentID, comment: text, author: Self.author, created: .now, updated: .now)
    }

    func deleteComment(_ commentID: Int, fromTask taskID: Int) async throws {
        deleteCommentCallCount += 1
    }
}

private struct FakeCommentCapabilityProvider: CapabilityProvider {
    let supportsAPIV2: Bool

    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "2.4.0", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        switch feature {
        case .apiV2:
            supportsAPIV2
        default:
            false
        }
    }
}
