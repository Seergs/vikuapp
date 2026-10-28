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

    public func fetchComments(taskID: EntityID) async throws -> [TaskComment] {
        guard let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskCommentRepositoryV2.fetchComments: the task must be synced first")
        }
        let envelope: APIv2Envelope<CommentDTO> = try await client.send(
            VikunjaEndpoints.commentsV2(taskID: resolvedTaskID),
        )
        return envelope.items.map(CommentMapper.toDomain)
    }

    public func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment {
        guard let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskCommentRepositoryV2.addComment: the task must be synced first")
        }
        let endpoint = try VikunjaEndpoints.createCommentV2(taskID: resolvedTaskID, text: text)
        let dto: CommentDTO = try await client.send(endpoint)
        return CommentMapper.toDomain(dto)
    }

    /// v2's `PUT .../comments/{id}` response is unreliable: on a real
    /// instance it comes back with `author: null` and a zero-value
    /// `created` (`0001-01-01T00:00:00Z`) — verified against
    /// `tasks.sergiosuarez.dev`, and `author` being non-optional on
    /// `CommentDTO` turns that `null` into a decode failure even though the
    /// update itself succeeded server-side. v2's `GET` of the same comment
    /// doesn't have this problem, so this sends the update, ignores its
    /// body, and re-fetches to get a trustworthy result — same spirit as
    /// `TaskMapper.merge`'s "don't trust an incomplete write response"
    /// workaround, minus the merge since a plain re-fetch is enough here.
    public func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment {
        guard let resolvedCommentID = commentID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure(
                "VikunjaTaskCommentRepositoryV2.updateComment: the task and comment must be synced first",
            )
        }
        let endpoint = try VikunjaEndpoints.updateCommentV2(
            taskID: resolvedTaskID, commentID: resolvedCommentID, text: text,
        )
        try await client.send(endpoint)
        let dto: CommentDTO = try await client.send(
            VikunjaEndpoints.commentV2(taskID: resolvedTaskID, commentID: resolvedCommentID),
        )
        return CommentMapper.toDomain(dto)
    }

    public func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws {
        guard let resolvedCommentID = commentID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure(
                "VikunjaTaskCommentRepositoryV2.deleteComment: the task and comment must be synced first",
            )
        }
        try await client.send(VikunjaEndpoints.deleteCommentV2(taskID: resolvedTaskID, commentID: resolvedCommentID))
    }
}
