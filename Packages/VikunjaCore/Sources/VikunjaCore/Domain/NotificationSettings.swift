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

    // MARK: - Codable

    /// The `legacy*` keys are the shape this type had before per-event
    /// granularity: one bool for both user-directed events, and one event
    /// set shared by every project the user had switched on. Decoding
    /// falls back to them so settings a user already configured aren't
    /// silently reset the first time this runs post-update.
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case userLevelEvents
        case projectEvents
        case legacyUserLevelEnabled = "userLevelEnabled"
        case legacyEnabledProjectIDs = "enabledProjectIDs"
        case legacyEnabledProjectEvents = "enabledProjectEvents"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)

        if let events = try container.decodeIfPresent(Set<WebhookEvent>.self, forKey: .userLevelEvents) {
            self.userLevelEvents = events
        } else {
            let wasEnabled = try container.decodeIfPresent(Bool.self, forKey: .legacyUserLevelEnabled) ?? false
            self.userLevelEvents = wasEnabled ? WebhookEvent.userDirected : []
        }

        if let perProject = try container.decodeIfPresent([Int: Set<WebhookEvent>].self, forKey: .projectEvents) {
            self.projectEvents = perProject
        } else if let sharedEvents = try container.decodeIfPresent(
            Set<WebhookEvent>.self,
            forKey: .legacyEnabledProjectEvents,
        ) {
            // Every switched-on project used to share one event set — seed
            // each of them with it so the next sync is a no-op rather than
            // silently dropping the user's existing selection.
            let legacyEnabledIDs = try container.decodeIfPresent(
                Set<Int>.self,
                forKey: .legacyEnabledProjectIDs,
            ) ?? []
            self.projectEvents = Dictionary(uniqueKeysWithValues: legacyEnabledIDs.map { ($0, sharedEvents) })
        } else {
            self.projectEvents = [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(userLevelEvents, forKey: .userLevelEvents)
        try container.encode(projectEvents, forKey: .projectEvents)
    }
}
