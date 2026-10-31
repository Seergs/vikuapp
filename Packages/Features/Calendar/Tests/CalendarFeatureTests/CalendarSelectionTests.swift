@testable import CalendarFeature
import Foundation
import Testing

struct CalendarSelectionTests {
    private let calendar = Calendar(identifier: .gregorian)
    /// Mid-month keeps adjacent-day selections inside the visible month.
    private let now = Date(timeIntervalSince1970: 1_734_264_000)

    @Test
    func `today button is hidden on opening`() {
        let selection = CalendarSelection(now: now, calendar: calendar)

        #expect(!selection.showsJumpToToday(now: now))
    }

    @Test(arguments: [-1, 1, 12])
    func `browsing another month shows today without changing the selected day`(delta: Int) {
        var selection = CalendarSelection(now: now, calendar: calendar)
        let selectedDay = selection.selectedDay

        selection.shiftMonth(by: delta)

        #expect(selection.selectedDay == selectedDay)
        #expect(selection.showsJumpToToday(now: now))
        selection.shiftMonth(by: -delta)
        #expect(!selection.showsJumpToToday(now: now))
    }

    @Test(arguments: [-1, 1])
    func `selecting another day in this month shows today`(delta: Int) throws {
        var selection = CalendarSelection(now: now, calendar: calendar)
        selection.selectedDay = try #require(calendar.date(byAdding: .day, value: delta, to: now))

        #expect(selection.showsJumpToToday(now: now))

        selection.selectedDay = now
        #expect(!selection.showsJumpToToday(now: now))
    }

    @Test
    func `returning to this month keeps today visible when another day is selected`() throws {
        var selection = CalendarSelection(now: now, calendar: calendar)
        selection.selectedDay = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        selection.shiftMonth(by: 1)
        selection.shiftMonth(by: -1)

        #expect(selection.showsJumpToToday(now: now))
    }

    @Test
    func `jump to today restores both the visible month and selected day`() throws {
        var selection = CalendarSelection(now: now, calendar: calendar)
        selection.shiftMonth(by: 1)
        selection.selectedDay = try #require(calendar.date(byAdding: .month, value: 1, to: now))

        selection.jumpToToday(now: now)

        #expect(calendar.isDate(selection.monthAnchor, equalTo: now, toGranularity: .month))
        #expect(selection.selectedDay == calendar.startOfDay(for: now))
        #expect(!selection.showsJumpToToday(now: now))
    }

    @Test
    func `jump uses the current day after midnight`() throws {
        var selection = CalendarSelection(now: now, calendar: calendar)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))

        #expect(selection.showsJumpToToday(now: tomorrow))
        selection.jumpToToday(now: tomorrow)

        #expect(selection.selectedDay == calendar.startOfDay(for: tomorrow))
        #expect(!selection.showsJumpToToday(now: tomorrow))
    }
}
