import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

/// Uses the same selection pattern as Appearance, scoped to the active account.
struct QuickAddMagicPickerView: View {
    let syntaxStore: QuickAddSyntaxStore

    @Environment(\.vikuPalette) private var palette
    @Environment(AppRouter.self) private var appRouter

    var body: some View {
        List {
            Section {
                ForEach(QuickAddMagicMode.allCases, id: \.self) { mode in
                    Button {
                        syntaxStore.setSyntax(mode.syntax)
                    } label: {
                        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                            Text(verbatim: mode.displayName)
                                .font(VikuFont.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            if isSelected(mode) {
                                Image(systemName: "checkmark")
                                    .font(VikuFont.footnote.weight(.semibold))
                                    .foregroundStyle(palette.brand)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected(mode) ? .isSelected : [])
                }
            }
            .listRowBackground(palette.cardBackground)

            if syntaxStore.failureMessage != nil || syntaxStore.syncStatus == .failed {
                Section {
                    if let failure = syntaxStore.failureMessage {
                        Text(verbatim: failure)
                            .font(VikuFont.footnote)
                            .foregroundStyle(palette.semanticDangerText)
                    }
                    if syntaxStore.syncStatus == .failed {
                        Button { syntaxStore.retrySync() } label: {
                            Text("Retry Magic sync", bundle: .module)
                        }
                    }
                }
                .listRowBackground(palette.cardBackground)
            }

            Section {
                Button {
                    appRouter.push(.documentationArticle("quick-add-shortcuts"))
                } label: {
                    Label {
                        Text("Quick Add Magic guide", bundle: .module)
                    } icon: {
                        Image(systemName: "book")
                    }
                    .font(VikuFont.body)
                    .foregroundStyle(palette.brand)
                }
            }
            .listRowBackground(palette.cardBackground)
        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(palette.pageBackground)
        .navigationTitle(Text("Quick Add Magic", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func isSelected(_ mode: QuickAddMagicMode) -> Bool {
        syntaxStore.hasKnownMode && QuickAddMagicMode(syntax: syntaxStore.syntax) == mode
    }
}
