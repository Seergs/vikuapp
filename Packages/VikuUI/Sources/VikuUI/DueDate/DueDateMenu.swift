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
    private let onSelect: (Date?) -> Void
    private let onCustom: () -> Void

    public init(currentDueDate: Date?, onSelect: @escaping (Date?) -> Void, onCustom: @escaping () -> Void) {
        self.currentDueDate = currentDueDate
        self.onSelect = onSelect
        self.onCustom = onCustom
    }

    public var body: some View {
        let selected = selectedShortcut()
        Menu(String(localized: "Due Date", bundle: .module), systemImage: "calendar") {
            ForEach(DueDateShortcut.allCases) { shortcut in
                Button {
                    onSelect(shortcut.resolvedDate())
                } label: {
                    HStack {
                        Text(String(localized: String.LocalizationValue(shortcut.titleKey), bundle: .module))
                        if shortcut == selected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button(String(localized: "Custom...", bundle: .module)) {
                onCustom()
            }
        }
    }

    /// The one quick pick that reads as "selected", mutually exclusive even
    /// when several options' resolved dates land on the same calendar day
    /// (e.g. on a Friday, "Tomorrow" and "Next Weekend" are both Saturday).
    /// A checkmark is a radio-button affordance, so exactly one option (or
    /// none) lights up; the tie goes to whichever option is listed first,
    /// the most specific phrasing of that day.
    private func selectedShortcut() -> DueDateShortcut? {
        guard let currentDueDate else { return DueDateShortcut.none }
        let calendar = Calendar.current
        return DueDateShortcut.allCases
            .first { shortcut in
                guard shortcut != .none, let resolved = shortcut.resolvedDate() else { return false }
                return calendar.isDate(currentDueDate, inSameDayAs: resolved)
            }
    }
}
