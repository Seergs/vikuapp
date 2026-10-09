import VikunjaCore

enum ReminderMapper {
    static func toDomain(_ dto: TaskReminderDTO) -> TaskReminder {
        TaskReminder(
            reminder: dto.reminder,
            relativePeriod: dto.relativePeriod,
            relativeTo: dto.relativeTo.flatMap(ReminderRelation.init(rawValue:)),
        )
    }

    static func toDTO(_ reminder: TaskReminder) -> TaskReminderDTO {
        TaskReminderDTO(
            reminder: reminder.reminder,
            relativePeriod: reminder.relativePeriod,
            relativeTo: reminder.relativeTo?.rawValue,
        )
    }
}
