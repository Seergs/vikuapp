import Foundation
import GRDB
import VikunjaCore

struct TaskReminderRecord: Codable, Equatable, Sendable {
    var localID: UUID
    var accountID: UUID
    var taskLocalID: UUID
    var position: Int
    var reminder: Date
    var relativePeriod: Int
    var relativeTo: ReminderRelation?
}

extension TaskReminderRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskReminder"
}

extension TaskReminderRecord {
    static func reminders(
        for taskLocalID: UUID,
        accountID: UUID,
        db: Database,
    ) throws -> [TaskReminder] {
        try rows(for: taskLocalID, accountID: accountID, db: db).map(\.taskReminder)
    }

    static func remindersByTaskLocalID(accountID: UUID, db: Database) throws -> [UUID: [TaskReminder]] {
        let rows = try TaskReminderRecord
            .filter(Column("accountID") == accountID)
            .order(Column("taskLocalID"), Column("position"))
            .fetchAll(db)
        return Dictionary(grouping: rows, by: \.taskLocalID)
            .mapValues { $0.map(\.taskReminder) }
    }

    static func replace(
        for taskLocalID: UUID,
        accountID: UUID,
        reminders: [TaskReminder],
        db: Database,
    ) throws {
        try TaskReminderRecord
            .filter(Column("accountID") == accountID)
            .filter(Column("taskLocalID") == taskLocalID)
            .deleteAll(db)
        for (position, reminder) in reminders.enumerated() {
            try TaskReminderRecord(
                localID: UUID(),
                accountID: accountID,
                taskLocalID: taskLocalID,
                position: position,
                reminder: reminder.reminder,
                relativePeriod: reminder.relativePeriod,
                relativeTo: reminder.relativeTo,
            ).insert(db)
        }
    }

    private static func rows(
        for taskLocalID: UUID,
        accountID: UUID,
        db: Database,
    ) throws -> [TaskReminderRecord] {
        try TaskReminderRecord
            .filter(Column("accountID") == accountID)
            .filter(Column("taskLocalID") == taskLocalID)
            .order(Column("position"))
            .fetchAll(db)
    }

    private var taskReminder: TaskReminder {
        TaskReminder(reminder: reminder, relativePeriod: relativePeriod, relativeTo: relativeTo)
    }
}
