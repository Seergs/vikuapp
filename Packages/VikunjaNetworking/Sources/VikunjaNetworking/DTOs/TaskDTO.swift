import Foundation

/// Tolerant mirror of the `/api/v1/tasks` JSON. Field names must be confirmed
/// against a real instance's swagger docs (`/api/v1/docs`) before integrating with
/// an actual Vikunja server — this is the only place to touch if the server changes
/// the shape of this resource.
struct TaskDTO: Codable {
    let id: Int
    let title: String
    let description: String?
    let done: Bool
    let dueDate: Date?
    let priority: Int?
    let projectId: Int
    /// Mirrors what the server reports; never written from
    /// `VikunjaTask.labels`. Vikunja manages a task's labels through the
    /// dedicated `/tasks/{id}/labels` endpoints
    /// (`LabelRepositoryProtocol.addLabel`/`removeLabel`) rather than the
    /// task body — same reasoning as `relatedTasks` below, and why
    /// `TaskMapper.toDTO`/`.merge` never populate this from `VikunjaTask`.
    let labels: [LabelDTO]?
    /// Keyed by Vikunja's relation-kind strings ("subtask", "blocked",
    /// "blocking", ...) — only the kinds `TaskMapper` currently reads are
    /// documented there; the rest tolerate decoding but are otherwise
    /// unused.
    ///
    /// This and every field below (`reminders` excepted — see its own doc
    /// comment) are never set by `VikunjaCore.VikunjaTask` — they exist
    /// purely so `TaskMapper.merge(_:onto:)` can carry a fetched task's full
    /// state through an update untouched. Vikunja's update endpoint is a
    /// full replace: any field missing from the request body gets reset to
    /// zero/null server-side rather than left alone
    /// (see https://github.com/go-vikunja/vikunja/issues/1459), so
    /// `VikunjaTaskRepository.update(_:)` fetches the current task first and
    /// only overwrites the fields it actually means to change — these
    /// properties are what make that safe. `assignees` stays opaque
    /// `JSONValue` rather than a concrete shape since its real structure
    /// isn't verified against live swagger docs, and guessing wrong would
    /// silently drop a sub-field — exactly the bug this exists to prevent.
    ///
    /// `var`, not `let`: a `let` property with a default value is excluded
    /// from the synthesized memberwise initializer entirely (Swift treats it
    /// as already fully initialized), which would make it impossible for
    /// `TaskMapper.merge(_:onto:)` to pass one through explicitly.
    var relatedTasks: [String: [RelatedTaskDTO]]?
    var doneAt: Date?
    var startDate: Date?
    var endDate: Date?
    /// Unlike the other fields in this group, `reminders` *is* set from
    /// `VikunjaCore.VikunjaTask.reminders` (`TaskMapper.toDTO`/`.merge`) —
    /// its shape (`TaskReminderDTO`) is verified against a live capture, so
    /// it's safe to round-trip through the domain model like `dueDate`/
    /// `priority` rather than staying opaque passthrough.
    var reminders: [TaskReminderDTO]?
    var repeatAfter: Int?
    var repeatMode: Int?
    var hexColor: String?
    var percentDone: Double?
    var assignees: [JSONValue]?
    var coverImageAttachmentId: Int?
    var isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case done
        case priority
        case labels
        case reminders
        case assignees
        case dueDate = "due_date"
        case projectId = "project_id"
        case relatedTasks = "related_tasks"
        case doneAt = "done_at"
        case startDate = "start_date"
        case endDate = "end_date"
        case repeatAfter = "repeat_after"
        case repeatMode = "repeat_mode"
        case hexColor = "hex_color"
        case percentDone = "percent_done"
        case coverImageAttachmentId = "cover_image_attachment_id"
        case isFavorite = "is_favorite"
    }
}
