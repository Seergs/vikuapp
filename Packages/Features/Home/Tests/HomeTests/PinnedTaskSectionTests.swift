import Foundation
@testable import Home
import Testing
import VikunjaCore

struct PinnedTaskSectionTests {
    private static let calendar = Calendar.current
    /// Fixed reference instant, same reasoning as `TodaySectionTests.now`:
    /// anchoring to noon keeps bucketing stable regardless of when the
    /// suite happens to run.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)) ?? Date()

    private static func days(_ value: Int) -> Date {
        calendar.date(byAdding: .day, value: value, to: now) ?? now
    }

    private static let yesterday = days(-1)
    private static let nextWeek = days(7)

    private static func sections(_ tasks: [VikunjaTask]) -> [PinnedTaskSection] {
        PinnedTaskSection.sections(from: tasks, now: now)
    }

    @Test
    func `groups tasks into overdue pending and completed`() {
        let overdueTask = VikunjaTask(id: 1, title: "Overdue", dueDate: Self.yesterday, projectID: 1)
        let pendingTask = VikunjaTask(id: 2, title: "Pending", dueDate: Self.nextWeek, projectID: 1)
        let completedTask = VikunjaTask(id: 3, title: "Completed", isDone: true, projectID: 1)

        let sections = Self.sections([overdueTask, pendingTask, completedTask])

        #expect(sections.map(\.title) == ["Overdue", "Pending", "Completed"])
        #expect(sections[0].tasks.map(\.id) == [1])
        #expect(sections[1].tasks.map(\.id) == [2])
        #expect(sections[2].tasks.map(\.id) == [3])
    }

    @Test
    func `includes tasks with no due date in the pending section`() {
        let noDueDate = VikunjaTask(id: 1, title: "Someday", projectID: 1)

        let sections = Self.sections([noDueDate])

        #expect(sections.map(\.title) == ["Pending"])
        #expect(sections[0].tasks.map(\.id) == [1])
    }

    @Test
    func `a done task is completed rather than overdue even past its due date`() {
        let doneOverdue = VikunjaTask(id: 1, title: "Done", isDone: true, dueDate: Self.yesterday, projectID: 1)

        let sections = Self.sections([doneOverdue])

        #expect(sections.map(\.title) == ["Completed"])
    }

    @Test
    func `empty input produces no sections`() {
        #expect(Self.sections([]).isEmpty)
    }

    @Test
    func `sorts each section by ascending due date with undated tasks last`() {
        let later = VikunjaTask(id: 1, title: "Later", dueDate: Self.nextWeek, projectID: 1)
        let undated = VikunjaTask(id: 2, title: "Undated", projectID: 1)
        let sooner = VikunjaTask(id: 3, title: "Sooner", dueDate: Self.days(1), projectID: 1)

        let sections = Self.sections([later, undated, sooner])

        #expect(sections.map(\.title) == ["Pending"])
        #expect(sections[0].tasks.map(\.id) == [3, 1, 2])
    }
}
