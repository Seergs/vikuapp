public protocol TaskCommentRepositoryProtocol: Sendable {
    func fetchComments(taskID: EntityID) async throws -> [TaskComment]
    func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment
    func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment
    func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws
}
