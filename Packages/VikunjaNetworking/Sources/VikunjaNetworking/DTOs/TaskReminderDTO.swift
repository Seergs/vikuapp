import Foundation

/// Mirrors Vikunja's `TaskReminder` JSON shape — confirmed against a live
/// instance's captured response (`Fixtures/task.json`) and `go-vikunja`'s
/// `pkg/models/task_reminder.go`. `id`/`task_id` are tagged `json:"-"`
/// server-side, so they never appear in the wire format; this only carries
/// the three fields that do.
struct TaskReminderDTO: Codable, Equatable {
    let reminder: Date
    var relativePeriod: Int
    /// Raw string rather than `VikunjaCore.ReminderRelation` directly — an
    /// unrecognized value (a newer Vikunja version added one) tolerates
    /// decoding here and is dropped by `ReminderMapper`, same pattern as
    /// `WebhookDTO.events`/`WebhookMapper`.
    var relativeTo: String?

    enum CodingKeys: String, CodingKey {
        case reminder
        case relativePeriod = "relative_period"
        case relativeTo = "relative_to"
    }
}
