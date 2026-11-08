import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

struct ReminderFormatterTests {
    @Test(arguments: [
        (-1800, "30 min before"),
        (1800, "30 min after"),
        (-3600, "1 h before"),
        (3600, "1 h after"),
        (-172_800, "2 days before"),
        (172_800, "2 days after"),
        (-1_209_600, "2 wk before"),
        (1_209_600, "2 wk after"),
        (0, "At due date"),
    ])
    func `chip shows quantity and direction without the long anchor`(seconds: Int, expected: String) {
        let reminder = TaskReminder(
            reminder: Date(timeIntervalSince1970: 1_794_574_800), relativePeriod: seconds, relativeTo: .dueDate,
        )
        #expect(ReminderFormatter.compactLabel(for: reminder) == expected)
    }

    @Test func `an absolute chip includes tomorrow and its specific time`() throws {
        let calendar = Calendar.current
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 12,
        )))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: reference))
        let date = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow))
        let reminder = TaskReminder(reminder: date)
        let text = ReminderFormatter.compactLabel(for: reminder, relativeTo: reference)
        #expect(text.hasPrefix("Tomorrow, "))
        #expect(text.contains(date.formatted(date: .omitted, time: .shortened)))
    }

    @Test func `full descriptions still include the anchor for editing and accessibility`() {
        let reminder = TaskReminder(
            reminder: Date(timeIntervalSince1970: 1_794_574_800), relativePeriod: -3600, relativeTo: .dueDate,
        )
        #expect(ReminderFormatter.label(for: reminder).contains("due date"))
        #expect(!ReminderFormatter.compactLabel(for: reminder).contains("due date"))
        #expect(ReminderFormatter.preciseLabel(for: reminder).contains(
            reminder.reminder.formatted(date: .omitted, time: .shortened),
        ))
    }
}
