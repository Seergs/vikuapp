import Foundation

public protocol TaskCommentRepositoryProtocol: Sendable {
    func fetchCommentSnapshot(taskID: EntityID) async throws -> TaskCommentSnapshot
    func fetchComments(taskID: EntityID) async throws -> [TaskComment]
    func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment
    func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment
    func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws
}

public extension TaskCommentRepositoryProtocol {
    /// Server-backed repositories complete a download on every successful read.
    /// Local repositories must override this to report persisted coverage.
    func fetchCommentSnapshot(taskID: EntityID) async throws -> TaskCommentSnapshot {
        let comments = try await fetchComments(taskID: taskID)
        return TaskCommentSnapshot(comments: comments, lastSuccessfulDownloadAt: Date())
    }
}
