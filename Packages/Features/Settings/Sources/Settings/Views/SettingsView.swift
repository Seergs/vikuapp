import Foundation
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

#if os(iOS)
import UIKit
#endif

/// The Settings tab's landing screen. The entry points here today are
/// appearance, connection management, and label management.
struct SettingsView: View {
    let activeAccountName: String
    let activeAccountHost: String
    let themeStore: AppThemeStoring
    let quickAddSyntaxStore: QuickAddSyntaxStore
    let badgeViewModel: AppIconBadgeViewModel
    let pendingSyncViewModel: PendingSyncViewModel
    let groupOverdueNotificationsViewModel: GroupOverdueNotificationsViewModel
    let defaultProjectViewModel: DefaultProjectSettingsViewModel
    let homeSelectionViewModel: HomeSelectionSettingsViewModel
    let isDevBuild: Bool
    let devBadgeStore: DevBadgeVisibilityStoring
    let networkLoggingStore: NetworkRequestLoggingStoring
    let whatsNewSeenVersionStore: WhatsNewSeenVersionStoring
    let onPreviewOnboarding: () -> Void
    let router: Router<SettingsRoute>

    @State private var isPresentingBadgeConsent = false
    @State private var isPresentingDefaultProjectPicker = false
    @State private var isPresentingHomeSelectionPicker = false
    @Environment(\.openURL) private var openURL
    @Environment(\.vikuPalette) private var palette

    var body: some View {
        List {
            // App-wide preferences — only Appearance navigates, to its own
            // picker screen; the rest here don't, unlike Connections/Manage
            // Labels below.
            Section {
                SettingsNavigationRow(
                    icon: "circle.lefthalf.filled",
                    title: String(localized: "Appearance", bundle: .module),
                    subtitle: themeStore.theme.displayName,
                ) {
                    router.push(.appearance)
                }

                Toggle(isOn: badgeEnabledBinding) {
                    HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                        SettingsRowIcon(systemName: "app.badge")
                        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                            Text("App Icon Badge", bundle: .module)
                            Text("Overdue and due-today tasks", bundle: .module)
                                .font(VikuFont.footnote)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }

                if badgeViewModel.isPermissionDenied {
                    badgeDeniedBanner
                }

                // TEMPORARY: ships alongside Push Notifications (see the
                // "This connection" section below), so it's gated the same
                // way for now. A follow-up ticket removes both gates together
                // once the feature is ready to ship.
                if isDevBuild {
                    Toggle(isOn: groupOverdueNotificationsBinding) {
                        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                            SettingsRowIcon(systemName: "bell.badge")
                            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                                Text("Group Overdue Notifications", bundle: .module)
                                Text("One alert instead of one per task", bundle: .module)
                                    .font(VikuFont.footnote)
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("General", bundle: .module)
            }
            .listRowBackground(palette.cardBackground)
            // Widens the gap to "This connection" below — confirmed good
            // with this override in place. iOS-only API, hence the guard
            // (mirrors `settingsListStyle()`).
            #if os(iOS)
            .listSectionSpacing(.custom(VikuSpacing.xl))
            #endif

            // One section, not several, so these render as a single grouped
            // card (matching Settings.app) instead of one card per row.
            // The avatar row shares the same `listRowBackground` as the rows
            // below it rather than floating on the plain page background —
            // giving it its own Section (so it could look visually distinct)
            // put it on the wrong side of the rounded-corner boundary (a
            // `List` Section only rounds its own first/last row), leaving
            // Manage Labels square-cornered with a stray separator line at
            // the seam, and cost an extra section-transition's worth of
            // vertical space that `.listSectionSpacing` couldn't fully claw
            // back. One Section — like "General" above, whose multiple rows
            // already look fine together — avoids both.
            Section {
                AccountSummaryRow(
                    connectionName: activeAccountName,
                    connectionHost: activeAccountHost,
                    userDisplayName: defaultProjectViewModel.accountDisplayName,
                ) {
                    router.push(.connections)
                }
                .listRowBackground(palette.cardBackground)

                SettingsNavigationRow(
                    icon: "tag",
                    title: String(localized: "Manage Labels", bundle: .module),
                    subtitle: String(localized: "View, edit, and create labels", bundle: .module),
                ) {
                    router.push(.manageLabels)
                }
                .listRowBackground(palette.cardBackground)

                SettingsNavigationRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: String(localized: "Pending Sync", bundle: .module),
                    subtitle: String(localized: "Changes waiting to upload", bundle: .module),
                ) {
                    router.push(.pendingSync)
                }
                .listRowBackground(palette.cardBackground)

                SettingsNavigationRow(
                    icon: "folder",
                    title: String(localized: "Default Project", bundle: .module),
                    subtitle: defaultProjectViewModel.defaultProjectTitle ?? String(localized: "None", bundle: .module),
                ) {
                    isPresentingDefaultProjectPicker = true
                }
                .listRowBackground(palette.cardBackground)

                SettingsNavigationRow(
                    icon: "house",
                    title: String(localized: "Home Screen", bundle: .module),
                    subtitle: homeSelectionViewModel.selectionTitle,
                ) {
                    isPresentingHomeSelectionPicker = true
                }
                .listRowBackground(palette.cardBackground)

                if let accountTimezone = defaultProjectViewModel.accountTimezone {
                    SettingsInfoRow(
                        icon: "clock",
                        title: String(localized: "Time Zone", bundle: .module),
                        value: accountTimezone,
                    )
                    .listRowBackground(palette.cardBackground)
                }

                // TEMPORARY: the Notifications screen isn't ready for
                // general release yet — dev-build-only for now so UI work
                // on it can still be previewed. A follow-up ticket removes
                // this gate (and "General"'s Group Overdue Notifications
                // gate above, which ships at the same time) once the
                // feature is ready to ship.
                if isDevBuild {
                    SettingsNavigationRow(
                        icon: "bell",
                        title: String(localized: "Push Notifications", bundle: .module),
                        subtitle: String(localized: "Enable alerts and choose events", bundle: .module),
                    ) {
                        router.push(.notifications)
                    }
                    .listRowBackground(palette.cardBackground)
                }
            } header: {
                Text("This connection", bundle: .module)
            } footer: {
                Text("Only applies to \(activeAccountName). Each connection has its own.", bundle: .module)
            }
            // Widens the gap to "Experimental" below — confirmed good with
            // this override in place; unaffected by the avatar row now
            // sharing this same Section (that only changed the no-longer-
            // relevant boundary above, between "This connection" and
            // Manage Labels, which doesn't exist anymore).
            #if os(iOS)
            .listSectionSpacing(.custom(VikuSpacing.xl))
            #endif

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
                        .foregroundStyle(palette.textSecondary)
                        .textCase(nil)
                }
            } footer: {
                Text(
                    "Shortcuts for new tasks. Todoist: #Project, @label, p1-p4. Vikunja: +Project, *label, !1-!5.",
                    bundle: .module,
                )
            }
            .listRowBackground(palette.cardBackground)

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
            .listRowBackground(palette.cardBackground)

            // Dev-only tools, never shown in a release build — see
            // `BuildConfig.isDevBuild`.
            if isDevBuild {
                Section {
                    #if DEBUG
                    Button(role: .destructive) {
                        Task { await pendingSyncViewModel.clearQueue() }
                    } label: {
                        Label {
                            Text("Clear Pending Sync Queue", bundle: .module)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(pendingSyncViewModel.isClearingQueue)
                    #endif

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

                    SettingsNavigationRow(
                        icon: "sparkles",
                        title: String(localized: "Reset What's New", bundle: .module),
                        subtitle: String(localized: "Show the sheet again on the next launch", bundle: .module),
                    ) {
                        whatsNewSeenVersionStore.setLastSeenReleaseVersion(nil)
                    }
                } header: {
                    Text("Developer", bundle: .module)
                }
                .listRowBackground(palette.cardBackground)
            }
        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(palette.pageBackground)
        .navigationTitle(Text("Settings", bundle: .module))
        .sheet(isPresented: $isPresentingBadgeConsent) {
            AppIconBadgeConsentSheet {
                Task { await badgeViewModel.confirmEnable() }
            }
        }
        .sheet(isPresented: $isPresentingDefaultProjectPicker) {
            ProjectPickerSheet(
                title: String(localized: "Default Project", bundle: .module),
                projects: defaultProjectViewModel.pickableProjects,
                selectedProjectID: defaultProjectViewModel.defaultProjectID.map(EntityID.remote),
                showsNoneOption: true,
            ) { project in
                Task { await defaultProjectViewModel.selectDefaultProject(project) }
            }
        }
        .sheet(isPresented: $isPresentingHomeSelectionPicker) {
            HomeSelectionPickerSheet(
                projects: homeSelectionViewModel.pickableProjects,
                selectedID: homeSelectionViewModel.selection?.id,
            ) { project in
                homeSelectionViewModel.select(project)
            }
        }
        .task {
            await badgeViewModel.refreshPermissionStatus()
        }
        .task {
            await defaultProjectViewModel.load()
        }
        .task {
            await homeSelectionViewModel.load()
        }
    }

    private var badgeDeniedBanner: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Notifications are turned off for Viku in iOS Settings.", bundle: .module)
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textSecondary)
            Button(String(localized: "Open Settings", bundle: .module)) {
                openSystemSettings()
            }
            .font(VikuFont.footnote)
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private var badgeEnabledBinding: Binding<Bool> {
        Binding(
            get: { badgeViewModel.isEnabled },
            set: { newValue in
                if newValue {
                    isPresentingBadgeConsent = true
                } else {
                    badgeViewModel.disable()
                }
            },
        )
    }

    private var quickAddSyntaxBinding: Binding<QuickAddSyntax?> {
        Binding(get: { quickAddSyntaxStore.syntax }, set: { quickAddSyntaxStore.setSyntax($0) })
    }

    private var groupOverdueNotificationsBinding: Binding<Bool> {
        Binding(
            get: { groupOverdueNotificationsViewModel.isEnabled },
            set: { newValue in Task { await groupOverdueNotificationsViewModel.setEnabled(newValue) } },
        )
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

    @Environment(\.vikuPalette) private var palette

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
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            // Without this, `.buttonStyle(.plain)` only treats the
            // icon/text/chevron themselves as tappable, not the transparent
            // gaps the `Spacer` leaves between them.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Connection section's lead row: the signed-in Vikunja user's avatar
/// (initials drawn from `userDisplayName`, not `connectionName`), the
/// connection's name in bold, and its host below it, plus a "Change" button
/// that opens the connections list. Unlike `SettingsNavigationRow`, only the
/// button navigates, so the name/host themselves stay non-interactive. A
/// `nil` `userDisplayName` (before `DefaultProjectSettingsViewModel.load()`
/// resolves) renders as a placeholder avatar rather than the row
/// disappearing.
private struct AccountSummaryRow: View {
    let connectionName: String
    let connectionHost: String
    let userDisplayName: String?
    let onChange: () -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            AccountAvatarView(userDisplayName: userDisplayName)

            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text(verbatim: connectionName)
                    .font(VikuFont.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(verbatim: connectionHost)
                    .font(VikuFont.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(String(localized: "Change", bundle: .module), action: onChange)
                .font(VikuFont.footnote)
                .buttonStyle(.borderless)
        }
    }
}

/// A circular avatar showing the signed-in user's initials in two letters, on
/// a brand-colored background — mirrors the system "contact initials" look
/// used elsewhere for accounts without a profile photo.
private struct AccountAvatarView: View {
    let userDisplayName: String?

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        Circle()
            .fill(palette.brand)
            .frame(width: 34, height: 34)
            .overlay {
                Text(verbatim: initials)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.brandForeground)
            }
    }

    private var initials: String {
        guard let userDisplayName else { return "?" }
        let words = userDisplayName.split(separator: " ").filter { !$0.isEmpty }
        switch words.count {
        case 0:
            return "?"
        case 1:
            return String(words[0].prefix(2)).uppercased()
        default:
            let first = words[0].first.map(String.init) ?? ""
            let second = words[1].first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
    }
}

/// A non-interactive settings row: tinted icon tile, title, and a trailing
/// value — for read-only account info like the Default Project row's time
/// zone, which has no editing flow yet and so doesn't navigate anywhere.
private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            SettingsRowIcon(systemName: icon)
            Text(verbatim: title)
                .font(VikuFont.body)
                .foregroundStyle(Color.primary)
            Spacer()
            Text(verbatim: value)
                .font(VikuFont.body)
                .foregroundStyle(palette.textSecondary)
        }
    }
}

/// The tinted icon tile shared by every settings row, plain or navigating.
/// Not file-private: `AboutView` reuses it for its own rows.
struct SettingsRowIcon: View {
    let systemName: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xs, style: .continuous)
            .fill(palette.brand.opacity(0.14))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.brand)
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
