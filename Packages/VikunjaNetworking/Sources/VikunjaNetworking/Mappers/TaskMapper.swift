import Foundation
import VikunjaCore

enum TaskMapper {
    /// Vikunja's API represents "no due date" as this zero-value timestamp rather than `null`.
    private static let noDueDateSentinel = ISO8601DateFormatter().date(from: "0001-01-01T00:00:00Z") ?? .distantPast

    private static func dueDate(from dto: TaskDTO) -> Date? {
        guard let dueDate = dto.dueDate, dueDate != noDueDateSentinel else { return nil }
        return dueDate
    }

    /// Reads one relation kind out of `dto.relatedTasks`, falling back to
    /// this task's own project for any entry missing its `project_id`.
    private static func relations(_ dto: TaskDTO, kind: String) -> [TaskRelation] {
        (dto.relatedTasks?[kind] ?? []).map { TaskRelationMapper.toDomain($0, fallbackProjectID: dto.projectId) }
    }

    /// The `subtask`/`blocked`/`blocking` kinds land in `VikunjaTask`'s
    /// dedicated fields; every other kind Vikunja reports goes here,
    /// keyed by `RelationKind`. An unrecognized kind string is dropped
    /// rather than crashing, matching `TaskDTO.relatedTasks`'s tolerant
    /// decoding.
    private static let namedRelationKinds: Set<String> = ["subtask", "blocked", "blocking"]

    private static func otherRelations(_ dto: TaskDTO) -> [RelationKind: [TaskRelation]] {
        guard let relatedTasks = dto.relatedTasks else { return [:] }
        var result: [RelationKind: [TaskRelation]] = [:]
        for (key, dtos) in relatedTasks where !namedRelationKinds.contains(key) {
            guard let kind = RelationKind(rawValue: key), !dtos.isEmpty else { continue }
            result[kind] = dtos.map { TaskRelationMapper.toDomain($0, fallbackProjectID: dto.projectId) }
        }
        return result
    }

    static func toDomain(_ dto: TaskDTO) -> VikunjaTask {
        VikunjaTask(
            id: dto.id,
            title: dto.title,
            description: dto.description,
            isDone: dto.done,
            dueDate: dueDate(from: dto),
            priority: VikunjaTask.Priority(rawValue: dto.priority ?? 0) ?? .unset,
            projectID: dto.projectId,
            labels: (dto.labels ?? []).map(LabelMapper.toDomain),
            subtasks: relations(dto, kind: "subtask"),
            dependsOn: relations(dto, kind: "blocked"),
            blocks: relations(dto, kind: "blocking"),
            otherRelations: otherRelations(dto),
            reminders: (dto.reminders ?? []).map(ReminderMapper.toDomain),
        )
    }

    /// `labels` is omitted (see `TaskDTO.labels`'s doc comment) — a newly
    /// created task starts with no labels; attach any via
    /// `LabelRepositoryProtocol.addLabel(_:toTask:)` once it has an id.
    /// `reminders` isn't omitted the same way: Vikunja has no dedicated
    /// reminders endpoint, so any reminder set before the task exists has to
    /// ride along in the create body.
    static func toDTO(_ task: VikunjaTask) -> TaskDTO {
        TaskDTO(
            id: task.id,
            title: task.title,
            description: task.description,
            done: task.isDone,
            dueDate: task.dueDate,
            priority: task.priority.rawValue,
            projectId: task.projectID,
            labels: nil,
            reminders: task.reminders.map(ReminderMapper.toDTO),
        )
    }

    /// Builds the safe body for `VikunjaTaskRepository.update(_:)`: starts
    /// from `current` (the task's just-fetched full state) and overwrites
    /// only the fields `VikunjaTask` tracks, leaving everything else —
    /// including fields our domain model doesn't represent at all — exactly
    /// as the server last reported them. See `TaskDTO`'s doc comment for why
    /// this exists. `reminders` is one of the fields `VikunjaTask` *does*
    /// track, so it's written from `task`, not carried over from `current`.
    static func merge(_ task: VikunjaTask, onto current: TaskDTO) -> TaskDTO {
        TaskDTO(
            id: current.id,
            title: task.title,
            description: task.description,
            done: task.isDone,
            dueDate: task.dueDate,
            priority: task.priority.rawValue,
            projectId: task.projectID,
            labels: current.labels,
            relatedTasks: current.relatedTasks,
            doneAt: current.doneAt,
            startDate: current.startDate,
            endDate: current.endDate,
            reminders: task.reminders.map(ReminderMapper.toDTO),
            repeatAfter: current.repeatAfter,
            repeatMode: current.repeatMode,
            hexColor: current.hexColor,
            percentDone: current.percentDone,
            assignees: current.assignees,
            coverImageAttachmentId: current.coverImageAttachmentId,
            isFavorite: current.isFavorite,
        )
    }
}
