import VikunjaCore

/// Derived from saved events and the relay filter so customization and presets agree.
enum ProjectNotificationPreset: Equatable, Sendable {
    case disabled
    case recommended
    case custom

    static let recommendedEvents: Set<WebhookEvent> = [.taskAssigneeCreated]

    init(events: Set<WebhookEvent>, assignmentMode: AssignmentNotificationMode) {
        if events.isEmpty {
            self = .disabled
        } else if events == Self.recommendedEvents, assignmentMode == .onlyMe {
            self = .recommended
        } else {
            self = .custom
        }
    }
}
