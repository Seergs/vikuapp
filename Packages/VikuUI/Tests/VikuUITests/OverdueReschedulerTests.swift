import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

@MainActor
struct OverdueReschedulerTests {
    private static let calendar = Calendar.current
    private static let now = calendar.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(),
    ) ?? Date()

    private var overdue: [VikunjaTask] {
        [
            VikunjaTask(id: 1, title: "Yesterday", projectID: 1),
            VikunjaTask(id: 2, title: "Last week", projectID: 1),
        ]
    }

    @Test(arguments: [DueDateShortcut.today, .tomorrow])
    func `submits each task once with the end of the chosen day`(shortcut: DueDateShortcut) async throws {
        let toast = FakeToastPresenter()
        let rescheduler = OverdueRescheduler(toastPresenter: toast)
        var submitted: [EntityID] = []
        var submittedDate: Date?

        await rescheduler.reschedule(
            overdue + [overdue[0]], to: shortcut, now: Self.now, calendar: Self.calendar,
        ) { ids, dueDate in
            submitted = ids
            submittedDate = dueDate
        }

        #expect(submitted == [1, 2])
        let expected = try #require(shortcut.resolvedDate(now: Self.now, calendar: Self.calendar))
        #expect(submittedDate == expected)
        let day = Self.calendar.date(byAdding: .day, value: shortcut == .today ? 0 : 1, to: Self.now)
        #expect(try Self.calendar.isDate(expected, inSameDayAs: #require(day)))
        #expect(rescheduler.completedCount == 1)
        #expect(!rescheduler.isRescheduling)
        #expect(toast.shownMessages.map(\.style) == [.success])
    }

    @Test func `a failed write reports one error and does not count as completed`() async {
        let toast = FakeToastPresenter()
        let rescheduler = OverdueRescheduler(toastPresenter: toast)

        await rescheduler.reschedule(overdue, to: .today, now: Self.now) { _, _ in
            throw VikunjaError.notFound
        }

        #expect(rescheduler.completedCount == 0)
        #expect(!rescheduler.isRescheduling)
        #expect(toast.shownMessages.map(\.style) == [.error])
    }

    @Test func `cancellation is silent so the tasks can be retried`() async {
        let toast = FakeToastPresenter()
        let rescheduler = OverdueRescheduler(toastPresenter: toast)

        await rescheduler.reschedule(overdue, to: .today, now: Self.now) { _, _ in
            throw CancellationError()
        }

        #expect(rescheduler.completedCount == 0)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `empty lists and other shortcuts never write`() async {
        let toast = FakeToastPresenter()
        let rescheduler = OverdueRescheduler(toastPresenter: toast)
        var calls = 0

        await rescheduler.reschedule([], to: .today, now: Self.now) { _, _ in calls += 1 }
        await rescheduler.reschedule(overdue, to: .nextWeek, now: Self.now) { _, _ in calls += 1 }
        await rescheduler.reschedule(overdue, to: .none, now: Self.now) { _, _ in calls += 1 }

        #expect(calls == 0)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `a second request while one is running is ignored`() async {
        let toast = FakeToastPresenter()
        let rescheduler = OverdueRescheduler(toastPresenter: toast)
        var calls = 0
        let tasks = overdue

        await rescheduler.reschedule(tasks, to: .today, now: Self.now) { _, _ in
            calls += 1
            #expect(rescheduler.isRescheduling)
            await rescheduler.reschedule(tasks, to: .tomorrow, now: Self.now) { _, _ in calls += 1 }
        }

        #expect(calls == 1)
        #expect(rescheduler.completedCount == 1)
    }
}
