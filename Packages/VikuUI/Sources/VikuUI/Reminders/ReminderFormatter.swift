import Foundation
import VikuDesignSystem
import VikunjaCore

/// Display phrasing for a `TaskReminder` in a list row — shared by
/// `ReminderPickerSheet` (so the sheet's own summary matches) and
/// `Features/Tasks`' reminders section.
public enum ReminderFormatter {
    public static func label(for reminder: TaskReminder) -> String {
        guard let relativeTo = reminder.relativeTo else {
            return DueDateFormatter.dueLabel(reminder.reminder)
        }
        return ReminderOffset.decompose(seconds: reminder.relativePeriod).localizedLabel(anchor: relativeTo)
    }
}
