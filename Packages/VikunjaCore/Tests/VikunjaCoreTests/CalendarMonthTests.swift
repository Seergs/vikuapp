import Foundation
import Testing
@testable import VikunjaCore

struct CalendarMonthTests {
    /// Monday-first Gregorian calendar in a fixed zone, so the grid layout is
    /// deterministic regardless of where the tests run.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private static func task(id: Int, due: Date, done: Bool = false, project: Int = 1) -> VikunjaTask {
        VikunjaTask(id: .remote(id), title: "Task \(id)", isDone: done, dueDate: due, projectID: .remote(project))
    }

    // September 2026: the 1st is a Tuesday, 30 days → 5 whole weeks (35 cells),
    // one leading day (Mon Aug 31) and four trailing (Oct 1-4).
    private static let anchor = date(2026, 9, 1)
    private static let now = date(2026, 9, 15)

    @Test
    func `grid is whole weeks starting on the calendar's first weekday`() {
        let month = CalendarMonth(containing: Self.anchor, tasks: [], now: Self.now, calendar: Self.calendar)

        #expect(month.weeks.count == 5)
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        #expect(month.weekdaySymbols.first == "M")

        let firstDay = month.weeks[0][0]
        #expect(Self.calendar.component(.weekday, from: firstDay.date) == Self.calendar.firstWeekday)
        #expect(firstDay.dayNumber == 31)
        #expect(firstDay.isInMonth == false)

        let lastDay = month.weeks[4][6]
        #expect(lastDay.dayNumber == 4)
        #expect(lastDay.isInMonth == false)
    }

    @Test
    func `marks today and places a task on its due day`() {
        let dueToday = Self.task(id: 1, due: Self.now)
        let month = CalendarMonth(containing: Self.anchor, tasks: [dueToday], now: Self.now, calendar: Self.calendar)

        let todayCell = month.weeks.flatMap(\.self).first { $0.isToday }
        #expect(todayCell?.dayNumber == 15)
        #expect(todayCell?.tasks.map(\.id) == [1])
        #expect(month.weeks.flatMap(\.self).filter(\.isToday).count == 1)
    }

    @Test
    func `a past day with a pending task reads as overdue, a done one does not`() {
        let pending = Self.task(id: 1, due: Self.date(2026, 9, 10))
        let done = Self.task(id: 2, due: Self.date(2026, 9, 11), done: true)
        let month = CalendarMonth(
            containing: Self.anchor,
            tasks: [pending, done],
            now: Self.now,
            calendar: Self.calendar,
        )
        let cells = month.weeks.flatMap(\.self)

        #expect(cells.first { $0.dayNumber == 10 && $0.isInMonth }?.hasOverduePending == true)
        #expect(cells.first { $0.dayNumber == 11 && $0.isInMonth }?.hasOverduePending == false)
    }

    @Test
    func `day dots are distinct pending projects capped at three`() {
        let due = Self.date(2026, 9, 20)
        let tasks = [
            Self.task(id: 1, due: due, project: 10),
            Self.task(id: 2, due: due, project: 10),
            Self.task(id: 3, due: due, project: 20),
            Self.task(id: 4, due: due, project: 30),
            Self.task(id: 5, due: due, project: 40),
            Self.task(id: 6, due: due, done: true, project: 50),
        ]
        let month = CalendarMonth(containing: Self.anchor, tasks: tasks, now: Self.now, calendar: Self.calendar)
        let cell = month.weeks.flatMap(\.self).first { $0.dayNumber == 20 && $0.isInMonth }

        #expect(cell?.dotProjectIDs == [10, 20, 30])
    }

    @Test
    func `offline tasks appear in both the day list and its project dots`() {
        let due = Self.date(2026, 9, 20)
        let localProject = EntityID.local(UUID())
        let offlineTask = VikunjaTask(
            id: .local(UUID()), title: "Offline task", dueDate: due, projectID: localProject,
        )
        let month = CalendarMonth(
            containing: Self.anchor, tasks: [offlineTask], now: Self.now, calendar: Self.calendar,
        )
        let cell = month.weeks.flatMap(\.self).first { $0.date == Self.calendar.startOfDay(for: due) }

        #expect(CalendarMonth.tasks(on: due, from: [offlineTask], calendar: Self.calendar) == [offlineTask])
        #expect(cell?.tasks == [offlineTask])
        #expect(cell?.dotProjectIDs == [localProject])
    }

    @Test
    func `mixed local and remote projects share the dot limit and exclude completed tasks`() {
        let due = Self.date(2026, 9, 20)
        let localProject = EntityID.local(UUID())
        let otherLocalProject = EntityID.local(UUID())
        let tasks = [
            Self.task(id: 1, due: due, project: 10),
            VikunjaTask(id: 2, title: "Local project", dueDate: due, projectID: localProject),
            VikunjaTask(id: 3, title: "Same project", dueDate: due, projectID: localProject),
            Self.task(id: 4, due: due, project: 20),
            VikunjaTask(id: 5, title: "Fourth project", dueDate: due, projectID: otherLocalProject),
        ]
        let month = CalendarMonth(containing: Self.anchor, tasks: tasks, now: Self.now, calendar: Self.calendar)
        let cell = month.weeks.flatMap(\.self).first { $0.date == Self.calendar.startOfDay(for: due) }

        #expect(cell?.dotProjectIDs == [.remote(10), localProject, .remote(20)])

        let completed = tasks.map { task in
            var task = task
            task.isDone = true
            return task
        }
        let completedMonth = CalendarMonth(
            containing: Self.anchor, tasks: completed, now: Self.now, calendar: Self.calendar,
        )
        let everyDotHidden = completedMonth.weeks.flatMap(\.self).allSatisfy(\.dotProjectIDs.isEmpty)
        #expect(everyDotHidden)
    }

    @Test
    func `an offline task in a synced project has a dot before and after synchronization`() {
        let due = Self.date(2026, 9, 20)
        let task = VikunjaTask(id: .local(UUID()), title: "Offline task", dueDate: due, projectID: 10)
        let offlineMonth = CalendarMonth(
            containing: Self.anchor, tasks: [task], now: Self.now, calendar: Self.calendar,
        )
        let syncedTask = VikunjaTask(id: 1, title: task.title, dueDate: due, projectID: task.projectID)
        let syncedMonth = CalendarMonth(
            containing: Self.anchor, tasks: [syncedTask], now: Self.now, calendar: Self.calendar,
        )

        let offlineCell = offlineMonth.weeks.flatMap(\.self).first { !$0.tasks.isEmpty }
        let syncedCell = syncedMonth.weeks.flatMap(\.self).first { !$0.tasks.isEmpty }
        #expect(offlineCell?.dotProjectIDs == [10])
        #expect(syncedCell?.dotProjectIDs == offlineCell?.dotProjectIDs)
    }

    @Test
    func `tasks on a day are pending first then ascending by due date`() {
        let day = Self.date(2026, 9, 20)
        let tasks = [
            Self.task(id: 1, due: Self.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day),
            Self.task(id: 2, due: Self.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day),
            Self.task(
                id: 3,
                due: Self.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day,
                done: true,
            ),
        ]

        let ordered = CalendarMonth.tasks(on: day, from: tasks, calendar: Self.calendar)

        #expect(ordered.map(\.id) == [2, 1, 3])
    }

    @Test
    func `tasks with no due date never appear`() {
        let noDue = VikunjaTask(id: 1, title: "Someday", projectID: 1)
        let month = CalendarMonth(containing: Self.anchor, tasks: [noDue], now: Self.now, calendar: Self.calendar)

        let everyCellEmpty = month.weeks.flatMap(\.self).allSatisfy(\.tasks.isEmpty)
        #expect(everyCellEmpty)
        #expect(CalendarMonth.tasks(on: Self.now, from: [noDue], calendar: Self.calendar).isEmpty)
    }

    @Test
    func `title is the capitalized month and year`() {
        let month = CalendarMonth(containing: Self.anchor, tasks: [], now: Self.now, calendar: Self.calendar)

        #expect(month.title == "September 2026")
    }
}
