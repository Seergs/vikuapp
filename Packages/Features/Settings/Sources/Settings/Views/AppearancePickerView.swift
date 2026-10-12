import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The destination pushed from `SettingsView`'s "Appearance" row: one row per
/// `AppTheme`, each with a preview icon (see `AppTheme.previewIcon`), its
/// name, and a checkmark on the active one. A plain `List` rather than a
/// `Picker`, since a `Picker`'s own collapsed summary mirrors whichever
/// option is selected — including its icon — which put a swatch on the
/// landing screen's row too where only the name was wanted.
struct AppearancePickerView: View {
    let themeStore: AppThemeStoring

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        List {
            Section {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button {
                        themeStore.setTheme(theme)
                    } label: {
                        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                            theme.previewIcon
                            Text(verbatim: theme.displayName)
                                .font(VikuFont.body)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if theme == themeStore.theme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.brand)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(palette.cardBackground)
        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(palette.pageBackground)
        .navigationTitle(Text("Appearance", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
