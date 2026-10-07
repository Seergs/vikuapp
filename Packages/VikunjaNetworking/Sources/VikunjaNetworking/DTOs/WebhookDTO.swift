import Foundation

/// Mirrors Vikunja's `Webhook` schema (identical shape in v1 and v2 — both
/// versions share the same `webhooks` DB table). `secret` is write-only: the
/// server never returns it, so it's only ever set when encoding a create
/// request. `projectID`/`userID` are mutually exclusive and server-assigned
/// (set from the URL, not the body) — `id` follows the rest of this
/// codebase's convention of `0` standing in for "not yet created" on a
/// request body (see `ProjectDTO`/`LabelDTO`).
struct WebhookDTO: Codable {
    let id: Int
    let targetURL: String
    let events: [String]?
    let projectID: Int?
    let userID: Int?
    let secret: String?
    let created: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case targetURL = "target_url"
        case events
        case projectID = "project_id"
        case userID = "user_id"
        case secret
        case created
    }
}
