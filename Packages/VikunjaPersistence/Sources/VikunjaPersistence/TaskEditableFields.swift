import Foundation
import GRDB
import VikunjaCore

/// The fields a full task edit writes. Subresources have independent operations
/// and must not turn an unchanged task edit into a conflict merely by bumping updated.
/// Dates use the wire's whole-second precision; reminder order is not significant.
struct TaskEditableFields: Codable, Equatable, Sendable {
    var title: String
    var description: String
    var isDone: Bool
    var dueDate: Date?
    var priority: Int
    var projectLocalID: UUID
    var reminders: [TaskReminder]

    init(
        title: String, description: String?, isDone: Bool, dueDate: Date?,
        priority: Int, projectLocalID: UUID, reminders: [TaskReminder],
    ) {
        self.title = title
        self.description = description ?? ""
        self.isDone = isDone
        self.dueDate = dueDate.map(Self.wholeSecond)
        self.priority = priority
        self.projectLocalID = projectLocalID
        self.reminders = reminders.map { reminder in
            var result = reminder
            // Relative reminders are defined by their anchor and offset. The
            // absolute timestamp is derived by the server, not another edit.
            result.reminder = reminder.relativeTo == nil ? Self.wholeSecond(reminder.reminder)
                : Date(timeIntervalSince1970: 0)
            if reminder.relativeTo == nil {
                result.relativePeriod = 0
            }
            return result
        }.sorted {
            let left = ($0.relativeTo?.rawValue ?? "", $0.relativePeriod, $0.reminder)
            let right = ($1.relativeTo?.rawValue ?? "", $1.relativePeriod, $1.reminder)
            return left < right
        }
    }

    init(_ task: VikunjaTask, projectLocalID: UUID) {
        self.init(
            title: task.title, description: task.description, isDone: task.isDone,
            dueDate: task.dueDate, priority: task.priority.rawValue,
            projectLocalID: projectLocalID, reminders: task.reminders,
        )
    }

    init(_ payload: TaskCreateOrUpdatePayload) {
        self.init(
            title: payload.title, description: payload.description, isDone: payload.isDone,
            dueDate: payload.dueDate, priority: payload.priority,
            projectLocalID: payload.projectLocalID, reminders: payload.reminders ?? [],
        )
    }

    static func cached(_ row: TaskRecord, db: Database) throws -> Self {
        try Self(
            title: row.title, description: row.description, isDone: row.isDone, dueDate: row.dueDate,
            priority: row.priority, projectLocalID: row.projectLocalID,
            reminders: TaskReminderRecord.reminders(for: row.localID, accountID: row.accountID, db: db),
        )
    }

    static func server(_ task: VikunjaTask, accountID: UUID, db: Database) throws -> Self? {
        let projects = try ProjectRecord.filter(Column("accountID") == accountID).fetchAll(db)
        guard let project = projects.first(where: {
            task.projectID == .local($0.localID) || task.projectID.remoteValue == $0.remoteID && $0.remoteID != nil
        }) else { return nil }
        return Self(task, projectLocalID: project.localID)
    }

    func applying(_ change: TaskBulkChange) -> Self {
        var result = self
        switch change {
        case let .completion(isDone): result.isDone = isDone
        case let .dueDate(date): result.dueDate = Self.wholeSecond(date)
        }
        return result
    }

    private static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

/// Kept separate from transport and queue acknowledgement so a future conflict
/// UI can use the same original/desired/current states without changing replay.
enum TaskEditEvaluation: Equatable {
    case unchanged
    case alreadyApplied
    case conflict

    static func compare(
        base: TaskEditableFields, desired: TaskEditableFields, current: TaskEditableFields?,
    ) -> Self {
        if current == desired {
            return .alreadyApplied
        }
        return current == base ? .unchanged : .conflict
    }
}

/// A queued edit keeps its original server base across local coalescing and pulls.
/// Legacy payloads deliberately retain a missing snapshot and use their old date check.
struct TaskEditBaseline {
    let fields: TaskEditableFields?
    let updatedAt: Date?

    static func capture(_ row: TaskRecord, db: Database) throws -> Self {
        let queue = try MutationQueueRecord.filter(Column("accountID") == row.accountID)
            .filter(Column("entityType") == MutationEntityType.task.rawValue)
            .filter(Column("targetLocalID") == row.localID).order(Column("id")).fetchAll(db)
        for item in queue where !item.needsConflictResolution {
            if item.operation == .update || item.operation == .create {
                let payload = try KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: item)
                return Self(fields: payload.baseFields, updatedAt: payload.baseUpdatedAt)
            }
            if item.operation.isBulkTaskChange {
                let intent = try TaskBulkIntent(item: item)
                return Self(fields: intent.baseFields, updatedAt: intent.baseUpdatedAt)
            }
        }
        return try Self(fields: row.remoteID == nil ? nil : .cached(row, db: db), updatedAt: row.serverUpdatedAt)
    }
}
