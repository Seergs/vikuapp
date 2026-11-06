import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The trailing "Reschedule" control of an Overdue section header. Its menu
/// offers `OverdueRescheduler.shortcuts`; the caller applies the choice to
/// every overdue task the section shows.
public struct RescheduleOverdueMenu: View {
    private let onSelect: (DueDateShortcut) -> Void

    @Environment(\.vikuPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(onSelect: @escaping (DueDateShortcut) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            Section {
                ForEach(OverdueRescheduler.shortcuts) { shortcut in
                    Button(String(localized: String.LocalizationValue(shortcut.titleKey), bundle: .module)) {
                        onSelect(shortcut)
                    }
                }
            } header: {
                Text("Move overdue tasks to", bundle: .module)
            }
        } label: {
            Text("Reschedule", bundle: .module)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(isEnabled ? palette.brand : palette.textSecondary)
                // Grow the tap area beyond the small label without
                // changing the header's height.
                .padding(.vertical, VikuSpacing.sm)
                .padding(.leading, VikuSpacing.md)
                .contentShape(Rectangle())
                .padding(.vertical, -VikuSpacing.sm)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}
