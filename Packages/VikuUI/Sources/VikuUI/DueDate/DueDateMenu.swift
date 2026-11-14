import SwiftUI
import VikunjaCore

/// The "Due Date" entry in a task's context/overflow menu: tapping it opens a
/// submenu of quick picks (None/Today/Tomorrow/Next Weekend/Next Week), the
/// same shortcuts Reminders offers, plus a trailing "Custom..." that falls
/// through to the full `DueDatePickerSheet`. A quick pick is applied
/// immediately via `onSelect`; `onCustom` only sets the caller's state to
/// present that sheet, since nothing here owns the sheet presentation.
public struct DueDateMenu: View {
    private let currentDueDate: Date?
    private let onSelect: @MainActor (Date?) -> Void
    private let onCustom: @MainActor () -> Void

    public init(currentDueDate: Date?, onSelect: @escaping @MainActor (Date?) -> Void, onCustom: @escaping @MainActor () -> Void) {
        self.currentDueDate = currentDueDate
        self.onSelect = onSelect
        self.onCustom = onCustom
    }

    public var body: some View {
        ContextMenuItems([Self.item(currentDueDate: currentDueDate, onSelect: onSelect, onCustom: onCustom)])
    }

    /// Resolves the same shortcuts for SwiftUI and stable native context menus.
    public static func item(
        currentDueDate: Date?, onSelect: @escaping @MainActor (Date?) -> Void, onCustom: @escaping @MainActor () -> Void,
        now: Date = Date(), calendar: Calendar = .current,
    ) -> ContextMenuItem {
        let selected = selectedShortcut(for: currentDueDate, now: now, calendar: calendar)
        let shortcuts = DueDateShortcut.allCases.map { shortcut in
            ContextMenuItem.action(
                shortcut.rawValue,
                title: String(localized: String.LocalizationValue(shortcut.titleKey), bundle: .module),
                isSelected: shortcut == selected,
            ) {
                onSelect(shortcut.resolvedDate())
            }
        }
        return .submenu(
            "dueDate", title: String(localized: "Due Date", bundle: .module), systemImage: "calendar",
            items: [
                .group("shortcuts", items: shortcuts),
                .group("custom", items: [
                    .action("customDate", title: String(localized: "Custom...", bundle: .module), perform: onCustom),
                ]),
            ],
        )
    }

    /// Use the first matching shortcut so overlapping dates have one checkmark.
    private static func selectedShortcut(for dueDate: Date?, now: Date, calendar: Calendar) -> DueDateShortcut? {
        guard let dueDate else { return DueDateShortcut.none }
        return DueDateShortcut.allCases.first { shortcut in
            guard shortcut != .none,
                  let resolved = shortcut.resolvedDate(now: now, calendar: calendar) else { return false }
            return calendar.isDate(dueDate, inSameDayAs: resolved)
        }
    }
}
