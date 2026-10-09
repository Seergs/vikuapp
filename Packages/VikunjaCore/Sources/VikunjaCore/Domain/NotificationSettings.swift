/// The user's push-notification preferences — what `WebhookSyncing`
/// reconciles Vikunja's webhooks against. Persisted by the composition root
/// (plain app storage, not the Keychain: none of this is a credential),
/// never read or written over the network directly.
public struct NotificationSettings: Equatable, Sendable, Codable {
    /// Master switch. `false` means no webhooks should exist for this
    /// device at all, regardless of the other fields below.
    public var isEnabled: Bool
    /// Which of the two user-directed events (`WebhookEvent.userDirected`)
    /// the user-level webhook should subscribe to. Empty means no
    /// user-level webhook at all.
    public var userLevelEvents: Set<WebhookEvent>
    /// Each project's event selection, keyed by project id. A project
    /// that's absent, or present with an empty set, means no webhook for
    /// that project — there's no separate "enabled but nothing selected"
    /// on/off state, selecting at least one event is what turns it on. Use
    /// `events(for:)` rather than reading this directly.
    public var projectEvents: [Int: Set<WebhookEvent>]

    public init(
        isEnabled: Bool = false,
        userLevelEvents: Set<WebhookEvent> = [],
        projectEvents: [Int: Set<WebhookEvent>] = [:],
    ) {
        self.isEnabled = isEnabled
        self.userLevelEvents = userLevelEvents
        self.projectEvents = projectEvents
    }

    /// `projectEvents[projectID]`, or empty if nothing's been selected for
    /// that project yet.
    public func events(for projectID: Int) -> Set<WebhookEvent> {
        projectEvents[projectID] ?? []
    }
}
