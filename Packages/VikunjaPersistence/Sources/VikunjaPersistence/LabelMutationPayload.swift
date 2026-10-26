import Foundation

/// The frozen "what the user wants" snapshot a queued `create`/`update`
/// replays against the server — see `ProjectCreateOrUpdatePayload`'s doc
/// comment for why this is captured once rather than read live from
/// `LabelRecord` at drain time. No `baseUpdatedAt` here, unlike the project
/// payload: Vikunja's label API exposes no `updated` timestamp this app
/// models, so there's no conflict baseline to compare against — a queued
/// label update is always just pushed.
struct LabelCreateOrUpdatePayload: Codable, Equatable, Sendable {
    var title: String
    var hexColor: String
}

/// What a queued `delete` needs to address the row server-side, since the
/// local row may already be gone by drain time.
struct LabelDeletePayload: Codable, Equatable, Sendable {
    var remoteID: Int
}
