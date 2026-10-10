/// The webhook event-name strings Vikunja's API accepts, verified against a
/// live 2.4+ instance's `/api/v2/openapi.json` (`GET /webhooks/events` for
/// the project-level list, `GET /user/settings/webhooks/events` for the
/// user-level subset). An unrecognized name coming back from the server
/// (a newer Vikunja version added one this enum doesn't know about yet) is
/// dropped by the mapper rather than failing the whole decode.
public enum WebhookEvent: String, Sendable, CaseIterable, Hashable, Codable {
    case taskCreated = "task.created"
    case taskUpdated = "task.updated"
    case taskDeleted = "task.deleted"
    case taskAssigneeCreated = "task.assignee.created"
    case taskAssigneeDeleted = "task.assignee.deleted"
    case taskCommentCreated = "task.comment.created"
    case taskCommentEdited = "task.comment.edited"
    case taskCommentDeleted = "task.comment.deleted"
    case taskAttachmentCreated = "task.attachment.created"
    case taskAttachmentDeleted = "task.attachment.deleted"
    case taskRelationCreated = "task.relation.created"
    case taskRelationDeleted = "task.relation.deleted"
    case projectUpdated = "project.updated"
    case projectDeleted = "project.deleted"
    case projectSharedUser = "project.shared.user"
    case projectSharedTeam = "project.shared.team"
    /// User-directed: a task assigned to (or created by, depending on
    /// server config) the webhook's owner became overdue.
    case taskOverdue = "task.overdue"
    /// User-directed: a reminder the webhook's owner set on a task fired.
    case taskReminderFired = "task.reminder.fired"

    /// The subset `/user/settings/webhooks/events` reports, i.e. the only
    /// events a user-level webhook may subscribe to. This is a one-way
    /// restriction: Vikunja's server-side validation (`Webhook.Create` in
    /// `pkg/models/webhooks.go`) only enforces it for a webhook with
    /// `UserID` set. A *project* webhook has no such restriction — it may
    /// subscribe to any event `/webhooks/events` lists, `taskOverdue`/
    /// `taskReminderFired` included, since the server registers both of
    /// them into that same pool via `RegisterUserDirectedEventForWebhook`
    /// (which calls `RegisterEventForWebhook` first). See `projectOrdered`.
    public static let userDirected: Set<WebhookEvent> = [.taskOverdue, .taskReminderFired]

    /// `userDirected`, in a stable display order. `taskOverdue` is listed
    /// last on purpose — `NotificationsView` appends the overdue-reminders
    /// time picker right after it, and that only reads as "this time is for
    /// Overdue Tasks" when the two rows are adjacent.
    public static let userDirectedOrdered: [WebhookEvent] = [.taskReminderFired, .taskOverdue]

    /// Every event a project-level webhook may subscribe to — every case,
    /// `userDirected` included (see its doc comment for why that's not
    /// excluded here), in declaration order.
    public static let projectOrdered: [WebhookEvent] = allCases
}
