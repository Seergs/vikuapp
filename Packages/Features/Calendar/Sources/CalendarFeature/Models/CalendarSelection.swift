import Foundation
import VikunjaCore

/// Keeps the visible month independent from the selected day's task list.
struct CalendarSelection {
    private let calendar: Calendar
    private(set) var monthAnchor: Date
    var selectedDay: Date

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        self.monthAnchor = calendar.startOfMonth(for: now)
        self.selectedDay = calendar.startOfDay(for: now)
    }

    func showsJumpToToday(now: Date = Date()) -> Bool {
        !calendar.isDate(monthAnchor, equalTo: now, toGranularity: .month)
            || !calendar.isDate(selectedDay, inSameDayAs: now)
    }

    mutating func shiftMonth(by delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = shifted
    }

    mutating func jumpToToday(now: Date = Date()) {
        monthAnchor = calendar.startOfMonth(for: now)
        selectedDay = calendar.startOfDay(for: now)
    }
}
