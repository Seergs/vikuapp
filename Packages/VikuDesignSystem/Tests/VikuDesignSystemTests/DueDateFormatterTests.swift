import Foundation
import Testing
@testable import VikuDesignSystem

struct DueDateFormatterTests {
    private let calendar = Calendar.current
    /// A fixed reference so the "same year" branch is deterministic.
    private let reference = { () -> Date in
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 9
        return Calendar.current.date(from: components) ?? .distantPast
    }()

    @Test
    func `today tomorrow and yesterday use relative names`() throws {
        #expect(DueDateFormatter.compact(reference, relativeTo: reference) == "Today")
        #expect(
            try DueDateFormatter.compact(
                #require(calendar.date(byAdding: .day, value: 1, to: reference)),
                relativeTo: reference,
            ) == "Tomorrow",
        )
        #expect(
            try DueDateFormatter.compact(
                #require(calendar.date(byAdding: .day, value: -1, to: reference)),
                relativeTo: reference,
            ) == "Yesterday",
        )
    }

    @Test
    func `within a week uses an abbreviated weekday`() throws {
        let inThreeDays = try #require(calendar.date(byAdding: .day, value: 3, to: reference))
        let expected = inThreeDays.formatted(.dateTime.weekday(.abbreviated))

        #expect(DueDateFormatter.compact(inThreeDays, relativeTo: reference) == expected)
    }

    @Test
    func `further out in the same year drops the year`() throws {
        let inTwoMonths = try #require(calendar.date(byAdding: .day, value: 60, to: reference))
        let expected = inTwoMonths.formatted(.dateTime.month(.abbreviated).day())

        let result = DueDateFormatter.compact(inTwoMonths, relativeTo: reference)
        #expect(result == expected)
        #expect(!result.contains("2026"))
    }

    @Test
    func `a different year keeps the year`() throws {
        let nextYear = try #require(calendar.date(byAdding: .day, value: 300, to: reference))
        let expected = nextYear.formatted(.dateTime.year().month(.abbreviated).day())

        #expect(DueDateFormatter.compact(nextYear, relativeTo: reference) == expected)
    }

    // MARK: - dueLabel

    /// Noon-anchored so adding hours in a test can't cross midnight (per CLAUDE.md).
    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reference) ?? reference
    }

    @Test
    func `dueLabel spells out today with the time`() throws {
        let afternoon = try #require(calendar.date(byAdding: .hour, value: 3, to: noon))
        let expected = "Today, \(afternoon.formatted(date: .omitted, time: .shortened))"

        #expect(DueDateFormatter.dueLabel(afternoon, relativeTo: noon) == expected)
    }

    @Test
    func `dueLabel uses relative names for tomorrow and yesterday`() throws {
        #expect(
            try DueDateFormatter.dueLabel(
                #require(calendar.date(byAdding: .day, value: 1, to: noon)),
                relativeTo: noon,
            ) == "Tomorrow",
        )
        #expect(
            try DueDateFormatter.dueLabel(
                #require(calendar.date(byAdding: .day, value: -1, to: noon)),
                relativeTo: noon,
            ) == "Yesterday",
        )
    }

    @Test
    func `dueLabel uses a wide weekday within a week`() throws {
        let inThreeDays = try #require(calendar.date(byAdding: .day, value: 3, to: noon))
        let expected = inThreeDays.formatted(.dateTime.weekday(.wide))

        #expect(DueDateFormatter.dueLabel(inThreeDays, relativeTo: noon) == expected)
    }

    @Test
    func `dueLabel falls back to an abbreviated date further out`() throws {
        let inTwoMonths = try #require(calendar.date(byAdding: .day, value: 60, to: noon))
        let expected = inTwoMonths.formatted(date: .abbreviated, time: .omitted)

        #expect(DueDateFormatter.dueLabel(inTwoMonths, relativeTo: noon) == expected)
    }
}
