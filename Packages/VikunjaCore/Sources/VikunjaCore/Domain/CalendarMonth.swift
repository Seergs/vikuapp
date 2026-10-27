import Foundation

/// The pure month-grid model behind the Calendar screen and the Calendar
/// widget: given the month to show plus the account's dated tasks, it produces
/// the weeks of day cells the view renders, each already carrying that day's
/// tasks. No SwiftUI, no networking, no `Color` — unit-tested like `TodayDigest`.
/// Lives in `VikunjaCore` (not `CalendarFeature`) so the screen and the widget
/// share one grid rule, the same way both build on `TodayDigest`.
///
/// A task lands on a day when its `dueDate` falls on that calendar day. Tasks
/// with no `dueDate` never appear on the calendar (same rule as the Today
/// screen — they only live inside their own project).
public struct CalendarMonth: Equatable, Sendable {
    /// One cell of the 7-column grid. Leading/trailing cells that spill over
    /// from the adjacent month are still real days (`isInMonth == false`), so
    /// the grid is always whole weeks.
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        public let dayNumber: Int
        public let isInMonth: Bool
        public let isToday: Bool
        /// Strictly before today — a pending task here is overdue.
        public let isPast: Bool
        /// This day's tasks, any completion state, ordered pending-first then
        /// ascending by due date, ties broken by id.
        public let tasks: [VikunjaTask]

        public var id: Date {
            date
        }

        public var pendingTasks: [VikunjaTask] {
            tasks.filter { !$0.isDone }
        }

        /// Whether the grid should draw this day's number in the danger color
        /// — a past day still holding pending tasks.
        public var hasOverduePending: Bool {
            isPast && !pendingTasks.isEmpty
        }

        /// Distinct project ids of this day's pending tasks, in first-seen
        /// order, capped at three — one status dot each under the day number.
        public var dotProjectIDs: [Int] {
            var seen: Set<Int> = []
            var result: [Int] = []
            for task in pendingTasks {
                // A task under a project that hasn't synced yet has no
                // remote id to look a color up by — it simply gets no dot
                // until its project resolves.
                guard let projectID = task.projectID.remoteValue, !seen.contains(projectID) else { continue }
                seen.insert(projectID)
                result.append(projectID)
                if result.count == 3 {
                    break
                }
            }
            return result
        }
    }

    /// Start of day of the first of the shown month.
    public let anchor: Date
    /// Localized "September 2026", capitalized for a header.
    public let title: String
    /// Seven very-short weekday symbols, rotated to start on the calendar's
    /// `firstWeekday` (Monday in most of Europe, Sunday in the US).
    public let weekdaySymbols: [String]
    /// Whole weeks of seven days each, in display order.
    public let weeks: [[Day]]

    public init(
        containing date: Date,
        tasks: [VikunjaTask],
        now: Date = Date(),
        calendar: Calendar = .current,
    ) {
        let startOfToday = calendar.startOfDay(for: now)
        let anchor = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date),
        ) ?? calendar.startOfDay(for: date)
        self.anchor = anchor

        self.title = Self.monthTitle(for: anchor, calendar: calendar)
        self.weekdaySymbols = Self.rotatedWeekdaySymbols(calendar: calendar)

        let tasksByDay = Dictionary(grouping: tasks.filter { $0.dueDate != nil }) { task in
            calendar.startOfDay(for: task.dueDate ?? now)
        }

        // The grid starts on the `firstWeekday` on or before the 1st, and runs
        // full weeks until it covers the whole month.
        let weekdayOfFirst = calendar.component(.weekday, from: anchor)
        let leadingDays = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: anchor) ?? anchor
        let daysInMonth = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
        let totalCells = Int((Double(leadingDays + daysInMonth) / 7).rounded(.up)) * 7

        var weeks: [[Day]] = []
        var week: [Day] = []
        for offset in 0 ..< totalCells {
            guard let cellDate = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let dayStart = calendar.startOfDay(for: cellDate)
            let dayTasks = Self.sorted(tasksByDay[dayStart] ?? [])
            week.append(
                Day(
                    date: dayStart,
                    dayNumber: calendar.component(.day, from: dayStart),
                    isInMonth: calendar.isDate(dayStart, equalTo: anchor, toGranularity: .month),
                    isToday: calendar.isDate(dayStart, inSameDayAs: startOfToday),
                    isPast: dayStart < startOfToday,
                    tasks: dayTasks,
                ),
            )
            if week.count == 7 {
                weeks.append(week)
                week = []
            }
        }
        if !week.isEmpty {
            weeks.append(week)
        }
        self.weeks = weeks
    }

    /// The task list for a tapped day, pending-first then ascending by due
    /// date (ties by id) — matches the selected-day section in the mock.
    public static func tasks(
        on day: Date,
        from tasks: [VikunjaTask],
        calendar: Calendar = .current,
    ) -> [VikunjaTask] {
        sorted(tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: day)
        })
    }

    private static func sorted(_ tasks: [VikunjaTask]) -> [VikunjaTask] {
        tasks.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone {
                return !lhs.isDone
            }
            let lhsDate = lhs.dueDate ?? .distantFuture
            let rhsDate = rhs.dueDate ?? .distantFuture
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id < rhs.id
        }
    }

    private static func monthTitle(for anchor: Date, calendar: Calendar) -> String {
        var formatStyle = Date.FormatStyle.dateTime.month(.wide).year()
        formatStyle.calendar = calendar
        formatStyle.timeZone = calendar.timeZone
        if let locale = calendar.locale {
            formatStyle.locale = locale
        }
        let raw = anchor.formatted(formatStyle)
        return raw.prefix(1).localizedCapitalized + raw.dropFirst()
    }

    private static func rotatedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
