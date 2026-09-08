import Foundation

/// Compact due-date phrasing for list rows and metadata lines.
///
/// `Text(date, style: .date)` renders the full localized date
/// ("September 6, 2026" / "6 de septiembre de 2026"), which wraps to several
/// lines inside a dense task row. This keeps it to one short token: relative
/// day names for the near future/past, a weekday name within a week, then a
/// day+month, adding the year only when it differs from the reference date.
///
/// Shared by every screen that shows a task's due date in a compact row
/// (`Features/Home`, `Features/Projects`, `Features/Search`) and the Today
/// widget, so the phrasing stays identical everywhere.
public enum DueDateFormatter {
    public static func compact(_ date: Date, relativeTo reference: Date = Date()) -> String {
        let calendar = Calendar.current
        let startOfReference = calendar.startOfDay(for: reference)
        let days = calendar.dateComponents(
            [.day],
            from: startOfReference,
            to: calendar.startOfDay(for: date),
        ).day ?? 0

        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: break
        }

        if abs(days) <= 6 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }

        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: reference)
        return sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    /// Fuller due-date phrasing for a task's detail screen, where there's room
    /// for the time of day and a spelled-out weekday. `compact(_:)` is the
    /// terse form for dense list rows; this one adds `Today`'s time, uses the
    /// wide weekday within a week, and falls back to an abbreviated date.
    public static func dueLabel(_ date: Date, relativeTo reference: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: reference) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: date),
        ).day ?? 0

        switch days {
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: break
        }

        if abs(days) <= 6 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
