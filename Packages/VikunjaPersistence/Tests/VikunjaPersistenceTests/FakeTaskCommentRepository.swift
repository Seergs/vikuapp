import Foundation
import VikunjaCore

final class FakeTaskCommentRepository: TaskCommentRepositoryProtocol, @unchecked Sendable {
    var comments: [TaskComment] = []
    var fetchError: VikunjaError?
    var addError: VikunjaError?
    var updateError: VikunjaError?
    var deleteError: VikunjaError?

    struct AddedComment: Equatable {
        let text: String
        let taskID: EntityID
    }

    struct UpdatedComment: Equatable {
        let commentID: EntityID
        let text: String
        let taskID: EntityID
    }

    struct DeletedComment: Equatable {
        let commentID: EntityID
        let taskID: EntityID
    }

    private(set) var fetchedTaskIDs: [EntityID] = []
    private(set) var addedComments: [AddedComment] = []
    private(set) var updatedComments: [UpdatedComment] = []
    private(set) var deletedComments: [DeletedComment] = []
    private var nextID = 1

    func fetchComments(taskID: EntityID) async throws -> [TaskComment] {
        fetchedTaskIDs.append(taskID)
        if let fetchError {
            throw fetchError
        }
        return comments
    }

    func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment {
        addedComments.append(AddedComment(text: text, taskID: taskID))
        if let addError {
            throw addError
        }
        let created = TaskComment(
            id: .remote(nextID),
            comment: text,
            author: User(id: 1, username: "me"),
            created: Date(),
            updated: Date(),
        )
        nextID += 1
        comments.append(created)
        return created
    }

    func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment {
        updatedComments.append(UpdatedComment(commentID: commentID, text: text, taskID: taskID))
        if let updateError {
            throw updateError
        }
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else {
            throw VikunjaError.notFound
        }
        comments[index].comment = text
        comments[index].updated = Date()
        return comments[index]
    }

    func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws {
        deletedComments.append(DeletedComment(commentID: commentID, taskID: taskID))
        if let deleteError {
            throw deleteError
        }
        comments.removeAll { $0.id == commentID }
    }
}
