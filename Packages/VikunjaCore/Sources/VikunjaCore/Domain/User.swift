import Foundation

public struct User: Identifiable, Equatable, Sendable {
    public let id: Int
    public var username: String
    public var name: String?
    public var email: String?
    /// The project new tasks default into (`default_project_id` on the Vikunja
    /// user), or `nil` when the user hasn't set one. Vikunja reports an unset
    /// value as `0`; the mapper normalizes that to `nil`.
    public var defaultProjectID: Int?
    /// The time of day, as `HH:mm` (24-hour), Vikunja checks this user's
    /// overdue tasks at (`overdue_tasks_reminders_time`). Drives both the
    /// server's daily "overdue tasks" email and, when the instance has
    /// webhooks enabled, the `task.overdue` webhook event regardless of
    /// whether the email is turned on — see `WebhookEvent.taskOverdue`.
    /// Interpreted in `timezone`, not the device's own time zone.
    public var overdueTasksRemindersTime: String?
    /// The IANA zone (e.g. `"Europe/Madrid"`) Vikunja interprets
    /// `overdueTasksRemindersTime` in, or `nil` when the user hasn't set one
    /// — the server then falls back to its own configured default (often
    /// `UTC`), which this app has no way to know ahead of time.
    public var timezone: String?

    public init(
        id: Int,
        username: String,
        name: String? = nil,
        email: String? = nil,
        defaultProjectID: Int? = nil,
        overdueTasksRemindersTime: String? = nil,
        timezone: String? = nil,
    ) {
        self.id = id
        self.username = username
        self.name = name
        self.email = email
        self.defaultProjectID = defaultProjectID
        self.overdueTasksRemindersTime = overdueTasksRemindersTime
        self.timezone = timezone
    }
}
