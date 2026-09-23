import Foundation
import VikunjaCore

/// v2 endpoint builders, added one resource at a time as each is migrated —
/// kept in a sibling file rather than growing `VikunjaEndpoints.swift` so a
/// resource's v1 and v2 paths stay easy to tell apart at a glance.
extension VikunjaEndpoints {
    /// Not used by any resource switch directly: `VikunjaCapabilityProvider
    /// .serverInfo()` only falls back to this from `/api/v1/info` on a 404,
    /// so this can never be the first call for an account. See its doc
    /// comment for why.
    static func infoV2() -> Endpoint {
        Endpoint(path: "/api/v2/info")
    }

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

    static func currentUserV2() -> Endpoint {
        Endpoint(path: "/api/v2/user")
    }

    static func tasksV2(projectID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(projectID)/tasks")
    }

    static func taskV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(id)")
    }

    static func createTaskV2(projectID: Int, dto: TaskDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/projects/\(projectID)/tasks", method: .post, body: dto)
    }

    static func updateTaskV2(id: Int, dto: TaskDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/tasks/\(id)", method: .put, body: dto)
    }

    static func deleteTaskV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(id)", method: .delete)
    }

    static func searchTasksV2(query: String) -> Endpoint {
        Endpoint(path: "/api/v2/tasks", queryItems: [URLQueryItem(name: "q", value: query)])
    }

    static func taskAttachmentsV2(taskID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/attachments")
    }

    static func uploadTaskAttachmentV2(taskID: Int, form: MultipartFormData) -> Endpoint {
        .multipart(path: "/api/v2/tasks/\(taskID)/attachments", method: .post, form: form)
    }

    static func downloadTaskAttachmentV2(
        taskID: Int,
        attachmentID: Int,
        previewSize: AttachmentPreviewSize?,
    ) -> Endpoint {
        let queryItems = previewSize.map { [URLQueryItem(name: "preview_size", value: $0.rawValue)] } ?? []
        return Endpoint(path: "/api/v2/tasks/\(taskID)/attachments/\(attachmentID)", queryItems: queryItems)
    }

    static func deleteTaskAttachmentV2(taskID: Int, attachmentID: Int) -> Endpoint {
        Endpoint(path: "/api/v2/tasks/\(taskID)/attachments/\(attachmentID)", method: .delete)
    }

    /// Verified against a real instance with local auth enabled
    /// (`vikunjademo.sergiosuarez.dev/api/v2/openapi.json` — the instance
    /// used for every other v2 verification in this migration has local
    /// auth disabled, so its spec omits this path entirely; Vikunja's
    /// OpenAPI spec is generated per-instance from its enabled features).
    /// Same request/response shape as v1's `/api/v1/login`.
    static func loginV2(_ credentials: LoginCredentials) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/login",
            method: .post,
            body: LoginRequestDTO(
                username: credentials.username,
                password: credentials.password,
                totpPasscode: credentials.totpPasscode,
                longToken: credentials.longToken,
            ),
        )
    }

    /// Same request/response shape as v1's OIDC callback, plus a new
    /// optional `totp_passcode` (2FA on an OIDC account) this app doesn't
    /// send yet — not a behavior change from v1, just an unused v2 addition.
    static func oidcCallbackV2(providerKey: String, code: String, scope: String, redirectURL: URL) throws -> Endpoint {
        try .encoding(
            path: "/api/v2/auth/openid/\(providerKey)/callback",
            method: .post,
            body: OIDCCallbackRequestDTO(code: code, scope: scope, redirectURL: redirectURL.absoluteString),
        )
    }

    /// Same request/response shape as v1's cookie-based refresh. Unlike
    /// `userTokenRenew()` (`/user/token`), which v2 narrows to link-share
    /// tokens only, this path keeps its v1 meaning in v2.
    static func userTokenRefreshV2(refreshToken: String) -> Endpoint {
        Endpoint(
            path: "/api/v2/user/token/refresh",
            method: .post,
            additionalHeaders: ["Cookie": "vikunja_refresh_token=\(refreshToken)"],
        )
    }
}
