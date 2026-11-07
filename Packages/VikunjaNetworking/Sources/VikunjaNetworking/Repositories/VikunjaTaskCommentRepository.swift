import Foundation
import VikunjaCore

public final class VikunjaTaskCommentRepository: TaskCommentRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchComments(taskID: EntityID) async throws -> [TaskComment] {
        guard let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskCommentRepository.fetchComments: the task must be synced first")
        }
        let (firstPage, response): ([CommentDTO], HTTPURLResponse) = try await client.sendWithResponse(
            VikunjaEndpoints.comments(taskID: resolvedTaskID),
        )
        var dtos = firstPage
        let totalPages = Int(response.value(forHTTPHeaderField: "x-pagination-total-pages") ?? "1") ?? 1
        if totalPages > 1 {
            for page in 2 ... totalPages {
                try Task.checkCancellation()
                let nextPage: [CommentDTO] = try await client.send(
                    VikunjaEndpoints.comments(taskID: resolvedTaskID, page: page),
                )
                dtos += nextPage
            }
        }
        return dtos.map(CommentMapper.toDomain)
    }

    public func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment {
        guard let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskCommentRepository.addComment: the task must be synced first")
        }
        let endpoint = try VikunjaEndpoints.createComment(taskID: resolvedTaskID, text: text)
        let dto: CommentDTO = try await client.send(endpoint)
        return CommentMapper.toDomain(dto)
    }

    public func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment {
        guard let resolvedCommentID = commentID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskCommentRepository.updateComment: the task and comment must be synced first")
        }
        let endpoint = try VikunjaEndpoints.updateComment(
            taskID: resolvedTaskID, commentID: resolvedCommentID, text: text,
        )
        let dto: CommentDTO = try await client.send(endpoint)
        return CommentMapper.toDomain(dto)
    }

    public func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws {
        guard let resolvedCommentID = commentID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskCommentRepository.deleteComment: the task and comment must be synced first")
        }
        try await client.send(VikunjaEndpoints.deleteComment(taskID: resolvedTaskID, commentID: resolvedCommentID))
    }
}
