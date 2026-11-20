/// The connection's push-notification preferences: webhook event selections
/// reconciled by `WebhookSyncing`, and relay delivery formatting. Persisted by the composition root
/// (plain app storage, not the Keychain: none of this is a credential),
/// never read or written over the network directly.
public struct NotificationSettings: Equatable, Sendable, Codable {
    /// Master switch. `false` means no webhooks should exist for this
    /// device at all, regardless of the other fields below.
    public var isEnabled: Bool
    /// Whether this connection's relay registration combines overdue tasks into one alert.
    /// Retained when push notifications or the overdue event are disabled.
    public var groupOverdueNotifications: Bool
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

    /// Last relay-confirmed filter, scoped to this account and project.
    public var projectAssignmentModes: [Int: AssignmentNotificationMode]

    public init(
        isEnabled: Bool = false,
        groupOverdueNotifications: Bool = false,
        userLevelEvents: Set<WebhookEvent> = [],
        projectEvents: [Int: Set<WebhookEvent>] = [:],
        projectAssignmentModes: [Int: AssignmentNotificationMode] = [:],
    ) {
        self.isEnabled = isEnabled
        self.groupOverdueNotifications = groupOverdueNotifications
        self.userLevelEvents = userLevelEvents
        self.projectEvents = projectEvents
        self.projectAssignmentModes = projectAssignmentModes
    }

    /// `projectEvents[projectID]`, or empty if nothing's been selected for
    /// that project yet.
    public func events(for projectID: Int) -> Set<WebhookEvent> {
        projectEvents[projectID] ?? []
    }
}

public extension NotificationSettings {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case groupOverdueNotifications
        case userLevelEvents
        case projectEvents
        case projectAssignmentModes
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        self.groupOverdueNotifications = try values.decodeIfPresent(
            Bool.self, forKey: .groupOverdueNotifications,
        ) ?? false
        self.userLevelEvents = try values.decode(Set<WebhookEvent>.self, forKey: .userLevelEvents)
        self.projectEvents = try values.decode([Int: Set<WebhookEvent>].self, forKey: .projectEvents)
        self.projectAssignmentModes = try values.decodeIfPresent(
            [Int: AssignmentNotificationMode].self, forKey: .projectAssignmentModes,
        ) ?? [:]
    }

    func assignmentMode(for projectID: Int) -> AssignmentNotificationMode {
        projectAssignmentModes[projectID] ?? .all
    }
}
