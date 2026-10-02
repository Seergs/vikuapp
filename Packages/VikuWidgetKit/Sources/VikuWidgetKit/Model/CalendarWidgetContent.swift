import Foundation
import VikunjaCore

/// One day cell of the calendar widget's month grid. A thin value type built
/// from `VikunjaCore.CalendarMonth.Day` — the widget's cached payload keeps only
/// what the grid draws, not the day's full `VikunjaTask` list.
public struct CalendarWidgetDay: Sendable, Hashable, Codable, Identifiable {
    public let date: Date
    public let dayNumber: Int
    public let isInMonth: Bool
    public let isToday: Bool
    /// A past day still holding pending tasks — the grid draws its number in
    /// the danger color, same as the Calendar screen.
    public let hasOverduePending: Bool
    /// Up to three project `hex_color` strings, one per distinct pending
    /// project on this day; `""` where a project's color is unset (the view
    /// resolves each through `Color(vikuHex:)` with a token fallback).
    public let dotColorHexes: [String]

    public var id: Date {
        date
    }

    public init(
        date: Date,
        dayNumber: Int,
        isInMonth: Bool,
        isToday: Bool,
        hasOverduePending: Bool,
        dotColorHexes: [String],
    ) {
        self.date = date
        self.dayNumber = dayNumber
        self.isInMonth = isInMonth
        self.isToday = isToday
        self.hasOverduePending = hasOverduePending
        self.dotColorHexes = dotColorHexes
    }
}

/// A flattened, display-ready task for the calendar widget's selected-day list.
/// Deliberately not a `VikunjaTask`, for the same reason as `TodayWidgetTask`.
public struct CalendarWidgetTask: Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let title: String
    public let isDone: Bool
    public let isOverdue: Bool
    public let projectName: String
    public let projectColorHex: String

    public init(
        id: Int,
        title: String,
        isDone: Bool,
        isOverdue: Bool,
        projectName: String,
        projectColorHex: String,
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.isOverdue = isOverdue
        self.projectName = projectName
        self.projectColorHex = projectColorHex
    }
}

/// The calendar widget's data for one render: the current month's grid plus the
/// current day's task list. Persisted to the App Group container so a failed
/// refresh can fall back to the last good render (`isStale == true`), exactly
/// like `TodayWidgetContent`.
public struct CalendarWidgetContent: Sendable, Hashable, Codable {
    public let accountName: String
    public let generatedAt: Date
    public var isStale: Bool
    /// Localized "September 2026", capitalized.
    public let monthTitle: String
    /// Seven very-short weekday symbols, rotated to the calendar's `firstWeekday`.
    public let weekdaySymbols: [String]
    /// Whole weeks of seven days each, in display order.
    public let weeks: [[CalendarWidgetDay]]
    /// Heading for the list under the grid — "Today".
    public let selectedDayLabel: String
    /// The current day's tasks, pending-first, capped at
    /// `VikuWidgetConfig.calendarTaskLimit`.
    public let todayTasks: [CalendarWidgetTask]
    /// The current day's task count before the cap, for a "+N more" hint.
    public let todayTaskCount: Int

    public init(
        accountName: String,
        generatedAt: Date,
        isStale: Bool = false,
        monthTitle: String,
        weekdaySymbols: [String],
        weeks: [[CalendarWidgetDay]],
        selectedDayLabel: String,
        todayTasks: [CalendarWidgetTask],
        todayTaskCount: Int,
    ) {
        self.accountName = accountName
        self.generatedAt = generatedAt
        self.isStale = isStale
        self.monthTitle = monthTitle
        self.weekdaySymbols = weekdaySymbols
        self.weeks = weeks
        self.selectedDayLabel = selectedDayLabel
        self.todayTasks = todayTasks
        self.todayTaskCount = todayTaskCount
    }

    /// Builds the content from a `CalendarMonth` and a project lookup, keeping
    /// the same grid and task order the Calendar screen renders.
    public static func make(
        month: CalendarMonth,
        projectsByID: [Int: Project],
        accountName: String,
        now: Date,
        calendar: Calendar = .current,
        taskLimit: Int = VikuWidgetConfig.calendarTaskLimit,
    ) -> CalendarWidgetContent {
        func hex(forProjectID id: Int) -> String {
            projectsByID[id]?.hexColor ?? ""
        }

        let weeks = month.weeks.map { week in
            week.map { day in
                CalendarWidgetDay(
                    date: day.date,
                    dayNumber: day.dayNumber,
                    isInMonth: day.isInMonth,
                    isToday: day.isToday,
                    hasOverduePending: day.hasOverduePending,
                    dotColorHexes: day.dotProjectIDs.map { hex(forProjectID: $0) },
                )
            }
        }

        let todayCell = month.weeks.flatMap(\.self).first { $0.isToday }
        let todayTasks = todayCell?.tasks ?? []
        let rows = todayTasks.prefix(taskLimit).map { task -> CalendarWidgetTask in
            let project = projectsByID[task.projectID]
            let overdue = !task.isDone && (task.dueDate.map { $0 < now } ?? false)
            return CalendarWidgetTask(
                id: task.id,
                title: task.title,
                isDone: task.isDone,
                isOverdue: overdue,
                projectName: project?.title ?? "",
                projectColorHex: project?.hexColor ?? "",
            )
        }

        return CalendarWidgetContent(
            accountName: accountName,
            generatedAt: now,
            monthTitle: month.title,
            weekdaySymbols: month.weekdaySymbols,
            weeks: weeks,
            selectedDayLabel: String(localized: "Today", bundle: .module),
            todayTasks: Array(rows),
            todayTaskCount: todayTasks.count,
        )
    }
}

/// What the calendar widget should render. `.content` covers both a fresh load
/// and a stale fallback — the view keys off `content.isStale` for the badge.
public enum CalendarWidgetState: Sendable, Hashable {
    /// No active account configured.
    case notConnected
    /// The server rejected the stored token (401).
    case needsAuth
    /// The refresh failed and there's no cached snapshot to fall back on.
    case unavailable
    case content(CalendarWidgetContent)
}

public extension CalendarWidgetContent {
    /// Sample data for the widget gallery and SwiftUI previews.
    static let placeholder: CalendarWidgetContent = {
        let calendar = Calendar.current
        let now = Date()
        let projects = [
            Project(id: 1, title: "Admin", hexColor: "#E85E00"),
            Project(id: 2, title: "Viku iOS", hexColor: "#196AFF"),
            Project(id: 3, title: "Home", hexColor: "#1FA669"),
        ]
        func task(_ id: Int, _ title: String, _ dayOffset: Int, project: Int, done: Bool = false) -> VikunjaTask {
            let due = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            return VikunjaTask(id: id, title: title, isDone: done, dueDate: due, projectID: project)
        }
        let tasks = [
            task(1, "Reply to the hosting invoice", -2, project: 1),
            task(2, "Draft the release notes", 0, project: 2),
            task(3, "Water the plants", 0, project: 3),
            task(4, "Book the dentist", 3, project: 3),
            task(5, "Review the pull request", 5, project: 2),
        ]
        let month = CalendarMonth(containing: now, tasks: tasks, now: now, calendar: calendar)
        return CalendarWidgetContent.make(
            month: month,
            projectsByID: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            accountName: "Viku",
            now: now,
            calendar: calendar,
        )
    }()
}
