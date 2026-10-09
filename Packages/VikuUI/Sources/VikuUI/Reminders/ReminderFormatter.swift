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

    /// The reminder's actual resolved date and time, regardless of mode —
    /// e.g. "Sun, Oct 11, 5:00 PM" — a secondary, precise reading alongside
    /// `label(for:)`'s relative-day or relative-offset phrasing (most useful
    /// for a relative reminder, whose `label(for:)` never shows a clock time
    /// at all).
    public static func preciseLabel(for reminder: TaskReminder) -> String {
        let date = reminder.reminder
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        let dayMonth = sameYear
            ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        return String(localized: "\(dayMonth), \(time)", bundle: .module)
    }
}
