import VikunjaCore

/// Derived from saved events so customization and presets always agree.
enum ProjectNotificationPreset: Equatable, Sendable {
    case disabled
    case recommended
    case custom

    static let recommendedEvents: Set<WebhookEvent> = [.taskAssigneeCreated, .taskCommentCreated]

    init(events: Set<WebhookEvent>) {
        if events.isEmpty {
            self = .disabled
        } else if events == Self.recommendedEvents {
            self = .recommended
        } else {
            self = .custom
        }
    }
}
