import Foundation

/// A quick due-date pick, the same handful of options Apple's Reminders app
/// offers before falling back to a full date picker. Pure date math only, no
/// UI/localization here, so a view layer can decide its own copy and leave
/// this testable without importing SwiftUI — same reasoning as `TaskSort`.
public enum DueDateShortcut: String, Sendable, CaseIterable, Hashable, Identifiable {
    case none
    case today
    case tomorrow
    case nextWeekend
    case nextWeek

    public var id: Self {
        self
    }

    /// The English source string a view layer uses as its String Catalog key
    /// for this option's title. Translation lives in the view layer's own
    /// catalog, not here.
    public var titleKey: String {
        switch self {
        case .none: "None"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeekend: "Next Weekend"
        case .nextWeek: "Next Week"
        }
    }

    /// The due date this option sets, or `nil` to clear it. Every non-`none`
    /// case resolves to 11:59:59 PM of its day, not midnight at its start —
    /// "today" has to mean "due sometime before today ends", never "due the
    /// instant today began". Midnight would read as already overdue the
    /// moment any time passes it, since overdue is an exact-time comparison
    /// (`dueDate < Date()`) elsewhere in the app.
    ///
    /// `.nextWeekend`/`.nextWeek` are always strictly in the future, even if
    /// `now` already falls on a Saturday/Monday: "next weekend"/"next week"
    /// never means "this instant".
    public func resolvedDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .none:
            return nil
        case .today:
            return Self.endOfDay(now, calendar: calendar)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return Self.endOfDay(tomorrow, calendar: calendar)
        case .nextWeekend:
            let saturday = calendar.nextDate(
                after: calendar.startOfDay(for: now),
                matching: DateComponents(weekday: 7),
                matchingPolicy: .nextTime,
            ) ?? now
            return Self.endOfDay(saturday, calendar: calendar)
        case .nextWeek:
            let monday = calendar.nextDate(
                after: calendar.startOfDay(for: now),
                matching: DateComponents(weekday: 2),
                matchingPolicy: .nextTime,
            ) ?? now
            return Self.endOfDay(monday, calendar: calendar)
        }
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}
