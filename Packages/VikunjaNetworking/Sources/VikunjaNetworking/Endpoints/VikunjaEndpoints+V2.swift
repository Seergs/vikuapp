import Foundation
import VikunjaCore

/// v2 endpoint builders, added one resource at a time per
/// `docs/API_V2_MIGRATION.md`'s migration order — kept in a sibling file
/// rather than growing `VikunjaEndpoints.swift` so a resource's v1 and v2
/// paths stay easy to tell apart at a glance.
extension VikunjaEndpoints {
    static func projectsV2() -> Endpoint {
        Endpoint(path: "/api/v2/projects")
    }

    static func projectV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(id)")
    }

    static func createProjectV2(dto: ProjectDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/projects", method: .post, body: dto)
    }

    static func updateProjectV2(id: Int, dto: ProjectDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/projects/\(id)", method: .put, body: dto)
    }

    static func deleteProjectV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(id)", method: .delete)
    }

    static func commentsV2(taskID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/comments")
    }

    static func commentV2(taskID: Int, commentID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/comments/\(commentID)")
    }

    static func createCommentV2(taskID: Int, text: String) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/tasks/\(taskID)/comments",
            method: .post,
            body: CommentRequestDTO(comment: text),
        )
    }

    static func updateCommentV2(taskID: Int, commentID: Int, text: String) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/tasks/\(taskID)/comments/\(commentID)",
            method: .put,
            body: CommentRequestDTO(comment: text),
        )
    }

    static func deleteCommentV2(taskID: Int, commentID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/comments/\(commentID)", method: .delete)
    }

    static func labelsV2() -> Endpoint {
        Endpoint(path: "/api/v2/labels")
    }

    static func createLabelV2(dto: LabelDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/labels", method: .post, body: dto)
    }

    static func updateLabelV2(id: Int, dto: LabelDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/labels/\(id)", method: .put, body: dto)
    }

    static func deleteLabelV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/labels/\(id)", method: .delete)
    }

    static func addLabelToTaskV2(taskID: Int, labelID: Int) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/tasks/\(taskID)/labels",
            method: .post,
            body: TaskLabelDTO(labelId: labelID),
        )
    }

    static func removeLabelFromTaskV2(taskID: Int, labelID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/labels/\(labelID)", method: .delete)
    }

    static func createTaskRelationV2(taskID: Int, kind: RelationKind, otherTaskID: Int) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/tasks/\(taskID)/relations",
            method: .post,
            body: CreateTaskRelationDTO(relationKind: kind.rawValue, otherTaskId: otherTaskID),
        )
    }

    static func deleteTaskRelationV2(taskID: Int, kind: RelationKind, otherTaskID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/relations/\(kind.rawValue)/\(otherTaskID)", method: .delete)
    }
}
