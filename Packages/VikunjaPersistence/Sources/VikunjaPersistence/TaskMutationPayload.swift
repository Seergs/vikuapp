import Foundation

/// The frozen "what the user wants" snapshot a queued `create`/`update`
/// replays against the server — see `ProjectCreateOrUpdatePayload`'s doc
/// comment for why this is captured once rather than read live from
/// `TaskRecord` at drain time.
struct TaskCreateOrUpdatePayload: Codable, Equatable, Sendable {
    var title: String
    var description: String?
    var isDone: Bool
    var dueDate: Date?
    var priority: Int
    /// The owning project's local id — resolved to a remote id at drain
    /// time the same way `ProjectCreateOrUpdatePayload.parentProjectLocalID`
    /// is, so a task queued under a project that's also only local-so-far
    /// still has somewhere to point until both sync.
    var projectLocalID: UUID
    /// This task's `serverUpdatedAt` as of when the mutation was queued —
    /// the conflict check's baseline. `nil` for a `create` (nothing on the
    /// server yet to conflict with).
    var baseUpdatedAt: Date?
}

/// What a queued `delete` needs to address the row server-side, since the
/// local row may already be gone by drain time.
struct TaskDeletePayload: Codable, Equatable, Sendable {
    var remoteID: Int
}
