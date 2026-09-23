import VikunjaCore

/// Routes each `TaskCommentRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource).
final class VikunjaTaskCommentRepositorySwitch: TaskCommentRepositoryProtocol {
    private let v1: TaskCommentRepositoryProtocol
    private let v2: TaskCommentRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: TaskCommentRepositoryProtocol, v2: TaskCommentRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> TaskCommentRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchComments(taskID: Int) async throws -> [TaskComment] {
        try await resolve().fetchComments(taskID: taskID)
    }

    func addComment(_ text: String, toTask taskID: Int) async throws -> TaskComment {
        try await resolve().addComment(text, toTask: taskID)
    }

    func updateComment(_ commentID: Int, text: String, onTask taskID: Int) async throws -> TaskComment {
        try await resolve().updateComment(commentID, text: text, onTask: taskID)
    }

    func deleteComment(_ commentID: Int, fromTask taskID: Int) async throws {
        try await resolve().deleteComment(commentID, fromTask: taskID)
    }
}
