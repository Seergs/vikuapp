import Foundation
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

/// The Settings tab's landing screen. The entry points here today are
/// appearance, connection management, and label management.
struct SettingsView: View {
    let activeAccountName: String
    let themeStore: AppThemeStoring
    let quickAddSyntaxStore: QuickAddSyntaxStore
    let isDevBuild: Bool
    let devBadgeStore: DevBadgeVisibilityStoring
    let networkLoggingStore: NetworkRequestLoggingStoring
    let onPreviewOnboarding: () -> Void
    let router: Router<SettingsRoute>

    var body: some View {
        List {
            // One section, not three, so these render as a single grouped
            // card (matching Settings.app) instead of one card per row.
            Section {
                Picker(selection: themeBinding) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(verbatim: theme.displayName).tag(theme)
                    }
                } label: {
                    HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                        SettingsRowIcon(systemName: "circle.lefthalf.filled")
                        Text("Appearance", bundle: .module)
                    }
                }

                SettingsNavigationRow(
                    icon: "server.rack",
                    title: String(localized: "Connections", bundle: .module),
                    subtitle: activeAccountName,
                ) {
                    router.push(.connections)
                }

                SettingsNavigationRow(
                    icon: "tag",
                    title: String(localized: "Manage Labels", bundle: .module),
                    subtitle: String(localized: "View, edit, and create labels", bundle: .module),
                ) {
                    router.push(.manageLabels)
                }
            }

            Section {
                Picker(selection: quickAddSyntaxBinding) {
                    Text("Off", bundle: .module).tag(QuickAddSyntax?.none)
                    ForEach(QuickAddSyntax.allCases, id: \.self) { syntax in
                        Text(verbatim: syntax.displayName).tag(QuickAddSyntax?.some(syntax))
                    }
                } label: {
                    HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                        SettingsRowIcon(systemName: "number")
                        Text("Quick-Add", bundle: .module)
                    }
                }
            } header: {
                // Features still being tried out live here, separate from the
                // stable settings above. Future experimental features go in this section.
                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    Text("Experimental", bundle: .module)
                    Text("Features still being tested. They may change or be removed.", bundle: .module)
                        .font(VikuFont.footnote)
                        .foregroundStyle(VikuColor.textSecondary)
                        .textCase(nil)
                }
            } footer: {
                Text(
                    "Shortcuts for new tasks. Todoist: #Project, @label, p1-p4. Vikunja: +Project, *label, !1-!5.",
                    bundle: .module,
                )
            }

            // Last, on its own: reference info, not something people change.
            Section {
                SettingsNavigationRow(
                    icon: "info.circle",
                    title: String(localized: "About", bundle: .module),
                    subtitle: String(localized: "Version, links, and privacy", bundle: .module),
                ) {
                    router.push(.about)
                }
            }

            // Dev-only tools, never shown in a release build — see
            // `BuildConfig.isDevBuild`.
            if isDevBuild {
                Section {
                    Toggle(isOn: devBadgeBinding) {
                        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                            SettingsRowIcon(systemName: "ladybug")
                            Text("Show DEV Badge", bundle: .module)
                        }
                    }

                    Toggle(isOn: networkLoggingBinding) {
                        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                            SettingsRowIcon(systemName: "network")
                            Text("Log Network Requests", bundle: .module)
                        }
                    }

                    SettingsNavigationRow(
                        icon: "arrow.counterclockwise",
                        title: String(localized: "Preview Onboarding", bundle: .module),
                        subtitle: String(localized: "See the first-launch screen again", bundle: .module),
                    ) {
                        onPreviewOnboarding()
                    }

                    // TEMPORARY: the Notifications screen isn't ready for
                    // general release yet — dev-build-only for now so UI
                    // work on it can still be previewed. A follow-up ticket
                    // removes this gate once the feature is ready to ship.
                    SettingsNavigationRow(
                        icon: "bell",
                        title: String(localized: "Notifications", bundle: .module),
                        subtitle: String(localized: "Push notifications via Viku Relay", bundle: .module),
                    ) {
                        router.push(.notifications)
                    }
                } header: {
                    Text("Developer", bundle: .module)
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(Text("Settings", bundle: .module))
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(get: { themeStore.theme }, set: { themeStore.setTheme($0) })
    }

    private var quickAddSyntaxBinding: Binding<QuickAddSyntax?> {
        Binding(get: { quickAddSyntaxStore.syntax }, set: { quickAddSyntaxStore.setSyntax($0) })
    }

    private var devBadgeBinding: Binding<Bool> {
        Binding(get: { devBadgeStore.isDevBadgeVisible }, set: { devBadgeStore.setDevBadgeVisible($0) })
    }

    private var networkLoggingBinding: Binding<Bool> {
        Binding(
            get: { networkLoggingStore.isNetworkRequestLoggingEnabled },
            set: { networkLoggingStore.setNetworkRequestLoggingEnabled($0) },
        )
    }
}

/// A tappable settings row: tinted icon tile, title, one-line subtitle, and a
/// trailing chevron. The whole row is the hit target.
private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                SettingsRowIcon(systemName: icon)

                VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                    Text(verbatim: title)
                        .font(VikuFont.body)
                        .foregroundStyle(Color.primary)
                    Text(verbatim: subtitle)
                        .font(VikuFont.footnote)
                        .foregroundStyle(VikuColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
            }
            // Without this, `.buttonStyle(.plain)` only treats the
            // icon/text/chevron themselves as tappable, not the transparent
            // gaps the `Spacer` leaves between them.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The tinted icon tile shared by every settings row, plain or navigating.
/// Not file-private: `AboutView` reuses it for its own rows.
struct SettingsRowIcon: View {
    let systemName: String

    var body: some View {
        RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xs, style: .continuous)
            .fill(VikuColor.brandPrimary.opacity(0.14))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VikuColor.brandPrimary)
            }
    }
}

/// Not file-private: `AboutView` uses the same list styling.
extension View {
    @ViewBuilder
    func settingsListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        self
        #endif
    }
}
