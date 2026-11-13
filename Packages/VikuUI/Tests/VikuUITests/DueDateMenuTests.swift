import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

@MainActor
struct DueDateMenuTests {
    private static let calendar = Calendar.current
    private static let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

    @Test(arguments: DueDateShortcut.allCases)
    func `resolved menu marks only the first matching shortcut`(shortcut: DueDateShortcut) throws {
        let dueDate = shortcut.resolvedDate(now: Self.now, calendar: Self.calendar)
        let item = DueDateMenu.item(
            currentDueDate: dueDate,
            onSelect: { _ in },
            onCustom: {},
            now: Self.now,
            calendar: Self.calendar,
        )
        let actions = try shortcuts(item)
        let selected = actions.filter { item in
            guard case let .action(isSelected, _, _) = item.content else { return false }
            return isSelected
        }
        let expected = DueDateShortcut.allCases.first { candidate in
            guard let dueDate else { return candidate == .none }
            guard let resolved = candidate.resolvedDate(now: Self.now, calendar: Self.calendar) else { return false }
            return Self.calendar.isDate(dueDate, inSameDayAs: resolved)
        }
        #expect(selected.map(\.id) == expected.map { [$0.rawValue] } ?? [])
    }

    @Test
    func `clear and custom commands preserve their callbacks`() throws {
        var selectedDate: Date? = Self.now
        var openedCustom = false
        let item = DueDateMenu.item(
            currentDueDate: Self.now,
            onSelect: { selectedDate = $0 },
            onCustom: { openedCustom = true },
        )
        let actions = try shortcuts(item)
        guard case let .action(_, _, clear) = try #require(actions.first).content,
              case let .submenu(groups) = item.content,
              case let .group(customActions) = try #require(groups.last).content,
              case let .action(_, _, custom) = try #require(customActions.first).content
        else { Issue.record("Expected clear and custom actions"); return }

        clear()
        custom()

        #expect(selectedDate == nil)
        #expect(openedCustom)
    }

    private func shortcuts(_ item: ContextMenuItem) throws -> [ContextMenuItem] {
        guard case let .submenu(groups) = item.content,
              case let .group(actions) = try #require(groups.first).content
        else { Issue.record("Expected due-date shortcuts"); return [] }
        return actions
    }
}
