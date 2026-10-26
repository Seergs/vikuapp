import Foundation

/// The frozen "what the user wants" snapshot a queued `create`/`update`
/// replays against the server — captured once, at the moment the mutation
/// was queued, rather than read live from `ProjectRecord` at drain time, so
/// draining several edits queued in sequence replays each one faithfully
/// instead of collapsing them into whatever the row currently holds.
struct ProjectCreateOrUpdatePayload: Codable, Equatable, Sendable {
    var title: String
    var description: String?
    var isArchived: Bool
    var isFavorite: Bool
    var parentProjectLocalID: UUID?
    var position: Double
    var hexColor: String
    /// This project's `serverUpdatedAt` as of when the mutation was queued —
    /// the conflict check's baseline. `nil` for a `create` (nothing on the
    /// server yet to conflict with).
    var baseUpdatedAt: Date?
}

/// What a queued `delete` needs to address the row server-side, since the
/// local row may already be gone by drain time.
struct ProjectDeletePayload: Codable, Equatable, Sendable {
    var remoteID: Int
}
