import Foundation

/// What a queued comment `create` needs at drain time: its text, plus the
/// task it belongs to. The comment side is the queue item's own
/// `targetLocalID`, so a comment queued against a task that hasn't synced yet
/// can defer until that task's own create resolves to a real remote id.
struct TaskCommentCreatePayload: Codable, Equatable, Sendable {
    var taskLocalID: UUID
    var text: String
}

/// Same shape as `TaskCommentCreatePayload` — the comment being edited is the
/// queue item's `targetLocalID`, and the task is repeated here so draining
/// doesn't have to walk back from the comment row (which may be gone if the
/// comment was deleted before its update drained).
struct TaskCommentUpdatePayload: Codable, Equatable, Sendable {
    var taskLocalID: UUID
    var text: String
}

/// What a queued `delete` needs to address the comment server-side, since the
/// local row is removed immediately (the composer should not keep showing a
/// comment whose deletion is only waiting for connectivity).
struct TaskCommentDeletePayload: Codable, Equatable, Sendable {
    var taskLocalID: UUID
    var remoteID: Int
}
