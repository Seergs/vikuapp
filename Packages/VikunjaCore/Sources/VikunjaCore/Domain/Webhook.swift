import Foundation

/// A webhook target, either project-scoped (`projectID` set) or user-scoped
/// (`userID` set) — the two are mutually exclusive on the server. `secret`
/// isn't modeled here: it's write-only on creation and the server never
/// returns it, so there's nothing to round-trip.
public struct Webhook: Identifiable, Equatable, Sendable {
    public let id: Int
    public var targetURL: URL
    public var events: [WebhookEvent]
    public let projectID: Int?
    public let userID: Int?
    public let createdAt: Date?

    public init(
        id: Int,
        targetURL: URL,
        events: [WebhookEvent],
        projectID: Int? = nil,
        userID: Int? = nil,
        createdAt: Date? = nil,
    ) {
        self.id = id
        self.targetURL = targetURL
        self.events = events
        self.projectID = projectID
        self.userID = userID
        self.createdAt = createdAt
    }
}
