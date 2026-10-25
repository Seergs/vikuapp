import Foundation
import Testing
import VikunjaCore
@testable import VikuWidgetKit

struct CalendarWidgetContentTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private static let now = date(2026, 9, 15)

    private static func task(id: Int, due: Date, done: Bool = false, project: Int = 1) -> VikunjaTask {
        VikunjaTask(id: id, title: "Task \(id)", isDone: done, dueDate: due, projectID: project)
    }

    @Test
    func `carries the grid, month title and weekday header from CalendarMonth`() {
        let month = CalendarMonth(containing: Self.now, tasks: [], now: Self.now, calendar: Self.calendar)
        let content = CalendarWidgetContent.make(
            month: month, projectsByID: [:], accountName: "Home", now: Self.now, calendar: Self.calendar,
        )

        #expect(content.monthTitle == "September 2026")
        #expect(content.weekdaySymbols.first == "M")
        #expect(content.weeks.count == month.weeks.count)
        #expect(content.weeks.allSatisfy { $0.count == 7 })
    }

    @Test
    func `a day's dots resolve to its pending projects' colors`() {
        let due = Self.date(2026, 9, 20)
        let tasks = [Self.task(id: 1, due: due, project: 10), Self.task(id: 2, due: due, project: 20)]
        let projects = [
            Project(id: 10, title: "A", hexColor: "#111111"),
            Project(id: 20, title: "B", hexColor: "#222222"),
        ]
        let month = CalendarMonth(containing: Self.now, tasks: tasks, now: Self.now, calendar: Self.calendar)
        let content = CalendarWidgetContent.make(
            month: month,
            projectsByID: Dictionary(
                uniqueKeysWithValues: projects.compactMap { project in project.id.remoteValue.map { ($0, project) } },
            ),
            accountName: "Home", now: Self.now, calendar: Self.calendar,
        )

        let cell = content.weeks.flatMap(\.self).first { $0.dayNumber == 20 && $0.isInMonth }
        #expect(cell?.dotColorHexes == ["#111111", "#222222"])
    }

    @Test
    func `today's tasks are listed and capped, with the pre-cap count kept`() {
        let tasks = (1 ... 6).map { Self.task(id: $0, due: Self.now) }
        let month = CalendarMonth(containing: Self.now, tasks: tasks, now: Self.now, calendar: Self.calendar)
        let content = CalendarWidgetContent.make(
            month: month, projectsByID: [:], accountName: "Home", now: Self.now,
            calendar: Self.calendar, taskLimit: 4,
        )

        #expect(content.todayTasks.count == 4)
        #expect(content.todayTaskCount == 6)
        #expect(content.selectedDayLabel == "Today")
    }

    @Test
    func `a task due earlier today reads as overdue`() {
        let earlier = Self.date(2026, 9, 15, hour: 8)
        let month = CalendarMonth(
            containing: Self.now, tasks: [Self.task(id: 1, due: earlier)], now: Self.now, calendar: Self.calendar,
        )
        let content = CalendarWidgetContent.make(
            month: month, projectsByID: [:], accountName: "Home", now: Self.now, calendar: Self.calendar,
        )

        #expect(content.todayTasks.first?.isOverdue == true)
    }
}
