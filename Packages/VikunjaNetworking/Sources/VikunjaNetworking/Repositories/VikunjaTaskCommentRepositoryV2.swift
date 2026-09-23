import VikunjaCore

/// v2 implementation of `TaskCommentRepositoryProtocol`. Reuses v1's
/// `CommentDTO` / `CommentMapper` rather than adding a `CommentDTOV2` —
/// verified against a real instance's `/api/v2/openapi.json`: v2's
/// `TaskComment` schema adds `reactions` (this app doesn't model reactions)
/// but `id`, `comment`, `author`, `created`, `updated` all have the same
/// name and type in both versions, including the nested `author` (v2's
/// `User` schema matches `UserDTO`'s fields exactly too).
public final class VikunjaTaskCommentRepositoryV2: TaskCommentRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchComments(taskID: Int) async throws -> [TaskComment] {
        let envelope: APIv2Envelope<CommentDTO> = try await client.send(VikunjaEndpoints.commentsV2(taskID: taskID))
        return envelope.items.map(CommentMapper.toDomain)
    }

    public func addComment(_ text: String, toTask taskID: Int) async throws -> TaskComment {
        let endpoint = try VikunjaEndpoints.createCommentV2(taskID: taskID, text: text)
        let dto: CommentDTO = try await client.send(endpoint)
        return CommentMapper.toDomain(dto)
    }

    public func updateComment(_ commentID: Int, text: String, onTask taskID: Int) async throws -> TaskComment {
        let endpoint = try VikunjaEndpoints.updateCommentV2(taskID: taskID, commentID: commentID, text: text)
        let dto: CommentDTO = try await client.send(endpoint)
        return CommentMapper.toDomain(dto)
    }

    public func deleteComment(_ commentID: Int, fromTask taskID: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteCommentV2(taskID: taskID, commentID: commentID))
    }
}
