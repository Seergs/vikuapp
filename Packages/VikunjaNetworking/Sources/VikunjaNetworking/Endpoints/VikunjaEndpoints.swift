import Foundation
import VikunjaCore

enum VikunjaEndpoints {
    static func info() -> Endpoint {
        Endpoint(path: "/api/v1/info")
    }

    static func login(_ credentials: LoginCredentials) throws -> Endpoint {
        try .encoding(
            path: "/api/v1/login",
            method: .post,
            body: LoginRequestDTO(
                username: credentials.username,
                password: credentials.password,
                totpPasscode: credentials.totpPasscode,
                longToken: credentials.longToken,
            ),
        )
    }

    /// Exchanges an OIDC authorization code for a Vikunja session. Mirrors
    /// Vikunja's Go `openid.Callback` struct (`code`, `scope`, `redirect_url`)
    /// — `redirectURL` must be the exact URI used in the authorization
    /// request that produced `code`; Vikunja's backend forwards it verbatim
    /// to the provider's token endpoint, which requires an exact match.
    static func oidcCallback(providerKey: String, code: String, scope: String, redirectURL: URL) throws -> Endpoint {
        try .encoding(
            path: "/api/v1/auth/openid/\(providerKey)/callback",
            method: .post,
            body: OIDCCallbackRequestDTO(code: code, scope: scope, redirectURL: redirectURL.absoluteString),
        )
    }

    /// Renews a still-valid JWT on pre-2.0 servers — Bearer-authed with that
    /// JWT itself, no body. On v2.0+ servers this rejects user tokens; use
    /// `userTokenRefresh(refreshToken:)` instead.
    static func userTokenRenew() -> Endpoint {
        Endpoint(path: "/api/v1/user/token", method: .post)
    }

    /// Renews a v2.0+ session using its refresh-token cookie (no Bearer
    /// header — the cookie itself is the credential, and rotates on use).
    static func userTokenRefresh(refreshToken: String) -> Endpoint {
        Endpoint(
            path: "/api/v1/user/token/refresh",
            method: .post,
            additionalHeaders: ["Cookie": "vikunja_refresh_token=\(refreshToken)"],
        )
    }

    static func tasks(projectID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectID)/tasks")
    }

    static func task(id: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(id)")
    }

    static func createTask(projectID: Int, dto: TaskDTO) throws -> Endpoint {
        try .encoding(path: "/api/v1/projects/\(projectID)/tasks", method: .put, body: dto)
    }

    static func updateTask(id: Int, dto: TaskDTO) throws -> Endpoint {
        try .encoding(path: "/api/v1/tasks/\(id)", method: .post, body: dto)
    }

    static func deleteTask(id: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(id)", method: .delete)
    }

    /// `GET /api/v1/tasks` (not `/tasks/all` — that path was renamed for
    /// consistency with other collection endpoints in
    /// go-vikunja/vikunja#1988; on a server past that change, the old path
    /// gets matched by `/tasks/{id}` instead, with `id="all"` failing to
    /// bind as an int — a 400 "Invalid model provided").
    static func searchTasks(query: String) -> Endpoint {
        Endpoint(path: "/api/v1/tasks", queryItems: [URLQueryItem(name: "s", value: query)])
    }

    static func projects() -> Endpoint {
        Endpoint(path: "/api/v1/projects")
    }

    static func project(id: Int) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(id)")
    }

    static func createProject(dto: ProjectDTO) throws -> Endpoint {
        try .encoding(path: "/api/v1/projects", method: .put, body: dto)
    }

    static func updateProject(id: Int, dto: ProjectDTO) throws -> Endpoint {
        try .encoding(path: "/api/v1/projects/\(id)", method: .post, body: dto)
    }

    static func deleteProject(id: Int) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(id)", method: .delete)
    }

    static func labels() -> Endpoint {
        Endpoint(path: "/api/v1/labels")
    }

    static func createLabel(dto: LabelDTO) throws -> Endpoint {
        try .encoding(path: "/api/v1/labels", method: .put, body: dto)
    }

    static func updateLabel(id: Int, dto: LabelDTO) throws -> Endpoint {
        try .encoding(path: "/api/v1/labels/\(id)", method: .post, body: dto)
    }

    static func deleteLabel(id: Int) -> Endpoint {
        Endpoint(path: "/api/v1/labels/\(id)", method: .delete)
    }

    static func addLabelToTask(taskID: Int, labelID: Int) throws -> Endpoint {
        try .encoding(
            path: "/api/v1/tasks/\(taskID)/labels",
            method: .put,
            body: TaskLabelDTO(labelId: labelID),
        )
    }

    static func removeLabelFromTask(taskID: Int, labelID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskID)/labels/\(labelID)", method: .delete)
    }

    static func createTaskRelation(taskID: Int, kind: RelationKind, otherTaskID: Int) throws -> Endpoint {
        try .encoding(
            path: "/api/v1/tasks/\(taskID)/relations",
            method: .put,
            body: CreateTaskRelationDTO(relationKind: kind.rawValue, otherTaskId: otherTaskID),
        )
    }

    static func deleteTaskRelation(taskID: Int, kind: RelationKind, otherTaskID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskID)/relations/\(kind.rawValue)/\(otherTaskID)", method: .delete)
    }

    static func comments(taskID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskID)/comments")
    }

    static func createComment(taskID: Int, text: String) throws -> Endpoint {
        try .encoding(
            path: "/api/v1/tasks/\(taskID)/comments",
            method: .put,
            body: CommentRequestDTO(comment: text),
        )
    }

    static func updateComment(taskID: Int, commentID: Int, text: String) throws -> Endpoint {
        try .encoding(
            path: "/api/v1/tasks/\(taskID)/comments/\(commentID)",
            method: .post,
            body: CommentRequestDTO(comment: text),
        )
    }

    static func deleteComment(taskID: Int, commentID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskID)/comments/\(commentID)", method: .delete)
    }

    static func taskAttachments(taskID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskID)/attachments")
    }

    static func uploadTaskAttachment(taskID: Int, form: MultipartFormData) -> Endpoint {
        .multipart(path: "/api/v1/tasks/\(taskID)/attachments", method: .put, form: form)
    }

    static func downloadTaskAttachment(
        taskID: Int,
        attachmentID: Int,
        previewSize: AttachmentPreviewSize?,
    ) -> Endpoint {
        let queryItems = previewSize.map { [URLQueryItem(name: "preview_size", value: $0.rawValue)] } ?? []
        return Endpoint(
            path: "/api/v1/tasks/\(taskID)/attachments/\(attachmentID)",
            queryItems: queryItems,
            timeoutInterval: Endpoint.attachmentTransferTimeout,
        )
    }

    static func deleteTaskAttachment(taskID: Int, attachmentID: Int) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskID)/attachments/\(attachmentID)", method: .delete)
    }

    static func currentUser() -> Endpoint {
        Endpoint(path: "/api/v1/user")
    }
}
