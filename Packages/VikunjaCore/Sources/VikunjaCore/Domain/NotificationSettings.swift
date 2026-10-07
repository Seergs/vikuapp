/// The user's push-notification preferences — what `WebhookSyncing`
/// reconciles Vikunja's webhooks against. Persisted by the composition root
/// (plain app storage, not the Keychain: none of this is a credential),
/// never read or written over the network directly.
public struct NotificationSettings: Equatable, Sendable, Codable {
    /// Master switch. `false` means no webhooks should exist for this
    /// device at all, regardless of the other fields below.
    public var isEnabled: Bool
    /// Whether the user-level webhook (`task.overdue` + `task.reminder.fired`
    /// — see `WebhookEvent.userDirected`) should exist. Unlike project-level
    /// events, this isn't itself configurable per event: the two user-
    /// directed events are both-or-nothing.
    public var userLevelEnabled: Bool
    /// Which projects should have a webhook. A project's absence here means
    /// "no webhook for this project", not "default events" — there's no
    /// partial/disabled state in between.
    public var enabledProjectIDs: Set<Int>
    /// The event set every enabled project's webhook subscribes to. Shared
    /// across all enabled projects rather than configured per project.
    public var enabledProjectEvents: Set<WebhookEvent>

    public init(
        isEnabled: Bool = false,
        userLevelEnabled: Bool = false,
        enabledProjectIDs: Set<Int> = [],
        enabledProjectEvents: Set<WebhookEvent> = NotificationSettings.defaultProjectEvents,
    ) {
        self.isEnabled = isEnabled
        self.userLevelEnabled = userLevelEnabled
        self.enabledProjectIDs = enabledProjectIDs
        self.enabledProjectEvents = enabledProjectEvents
    }

    /// The default project-level events: task created, updated, assigned,
    /// commented.
    public static let defaultProjectEvents: Set<WebhookEvent> = [
        .taskCreated,
        .taskUpdated,
        .taskAssigneeCreated,
        .taskCommentCreated,
    ]
}
