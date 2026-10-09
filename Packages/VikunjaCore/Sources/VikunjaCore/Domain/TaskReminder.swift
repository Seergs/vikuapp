import Foundation

/// A reminder attached to a task. Vikunja always stores an absolute
/// `reminder` timestamp — for a relative reminder (`relativeTo` set), the
/// server (re)computes that timestamp from the task's matching date
/// whenever it changes, so `reminder` is a snapshot of that computation
/// rather than a value this client derives itself.
public struct TaskReminder: Equatable, Hashable, Sendable {
    public var reminder: Date
    /// Offset in seconds from `relativeTo`'s date; negative fires before it,
    /// positive after. Only meaningful when `relativeTo` is set.
    public var relativePeriod: Int
    /// The task date this reminder is anchored to, or `nil` for an absolute
    /// reminder (the common case — only `reminder` matters then).
    public var relativeTo: ReminderRelation?

    public init(reminder: Date, relativePeriod: Int = 0, relativeTo: ReminderRelation? = nil) {
        self.reminder = reminder
        self.relativePeriod = relativePeriod
        self.relativeTo = relativeTo
    }
}

/// The task date field a relative `TaskReminder.relativeTo` anchors to.
/// Verified against `go-vikunja`'s `ReminderRelation` type
/// (`pkg/models/task_reminder.go`): `due_date`, `start_date`, `end_date`.
public enum ReminderRelation: String, Sendable, CaseIterable, Hashable, Codable {
    case dueDate = "due_date"
    case startDate = "start_date"
    case endDate = "end_date"
}
