import Foundation
import VikuDesignSystem
import VikunjaCore

/// Display phrasing for a `TaskReminder` in a list row — shared by
/// `ReminderPickerSheet` (so the sheet's own summary matches) and
/// `Features/Tasks`' reminders section.
public enum ReminderFormatter {
    /// Short chip copy. Keep `label(for:)` and `preciseLabel(for:)` for
    /// editing and accessibility, where the anchor and full date matter.
    public static func compactLabel(for reminder: TaskReminder, relativeTo reference: Date = Date()) -> String {
        guard let anchor = reminder.relativeTo else {
            let day = DueDateFormatter.compact(reminder.reminder, relativeTo: reference)
            let time = reminder.reminder.formatted(date: .omitted, time: .shortened)
            return String(localized: "\(day), \(time)", bundle: .module)
        }
        let offset = ReminderOffset.decompose(seconds: reminder.relativePeriod)
        guard offset.quantity > 0 else {
            return anchor == .dueDate
                ? String(localized: "At due date", bundle: .module)
                : label(for: reminder)
        }
        let quantity = offset.quantity
        return switch (offset.unit, offset.direction) {
        case (.minutes, .before): String(localized: "\(quantity) min before", bundle: .module)
        case (.minutes, .after): String(localized: "\(quantity) min after", bundle: .module)
        case (.hours, .before): String(localized: "\(quantity) h before", bundle: .module)
        case (.hours, .after): String(localized: "\(quantity) h after", bundle: .module)
        case (.days, .before): String(localized: "\(quantity) days before", bundle: .module)
        case (.days, .after): String(localized: "\(quantity) days after", bundle: .module)
        case (.weeks, .before): String(localized: "\(quantity) wk before", bundle: .module)
        case (.weeks, .after): String(localized: "\(quantity) wk after", bundle: .module)
        }
    }

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
