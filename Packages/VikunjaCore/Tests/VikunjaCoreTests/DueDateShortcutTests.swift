import Foundation
import Testing
@testable import VikunjaCore

/// Anchors every case to noon on a known historical date (Jan 1, 2024 was a
/// Monday) rather than `Date()`, so weekday math is deterministic regardless
/// of when the suite runs.
struct DueDateShortcutTests {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func date(year: Int = 2024, month: Int = 1, day: Int) -> Date {
        calendar.date(
            bySettingHour: 12, minute: 0, second: 0,
            of: calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(),
        ) ?? Date()
    }

    private static func endOfDay(day: Int) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date(day: day)) ?? Date()
    }

    private static let monday = date(day: 1)
    private static let wednesday = date(day: 3)
    private static let saturday = date(day: 6)

    @Test func `none clears the due date`() {
        #expect(DueDateShortcut.none.resolvedDate(now: Self.wednesday, calendar: Self.calendar) == nil)
    }

    @Test func `today resolves to end of today`() {
        let expected = Self.endOfDay(day: 3)
        #expect(DueDateShortcut.today.resolvedDate(now: Self.wednesday, calendar: Self.calendar) == expected)
    }

    @Test func `tomorrow resolves to end of next day`() {
        let expected = Self.endOfDay(day: 4)
        #expect(DueDateShortcut.tomorrow.resolvedDate(now: Self.wednesday, calendar: Self.calendar) == expected)
    }

    @Test func `next weekend resolves to the upcoming saturday`() {
        let expected = Self.endOfDay(day: 6)
        #expect(DueDateShortcut.nextWeekend.resolvedDate(now: Self.wednesday, calendar: Self.calendar) == expected)
    }

    @Test func `next weekend skips today when today is already saturday`() {
        let expected = Self.endOfDay(day: 13)
        #expect(DueDateShortcut.nextWeekend.resolvedDate(now: Self.saturday, calendar: Self.calendar) == expected)
    }

    @Test func `next week resolves to the upcoming monday`() {
        let expected = Self.endOfDay(day: 8)
        #expect(DueDateShortcut.nextWeek.resolvedDate(now: Self.wednesday, calendar: Self.calendar) == expected)
    }

    @Test func `next week skips today when today is already monday`() {
        let expected = Self.endOfDay(day: 8)
        #expect(DueDateShortcut.nextWeek.resolvedDate(now: Self.monday, calendar: Self.calendar) == expected)
    }
}
