import Foundation
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

#if os(iOS)
import UIKit
#endif

/// The push-notification opt-in screen: a master toggle gated behind
/// `NotificationsConsentSheet`, and — once enabled — individual checkboxes
/// for the two user-directed events, plus a searchable list of projects that
/// drills into `ProjectNotificationsView` for that project's own event
/// selection (there's no separate per-project on/off switch: selecting an
/// event there is what turns it on). See `NotificationsViewModel` for the
/// sync that keeps Vikunja's webhooks matching whatever's shown here.
struct NotificationsView: View {
    let viewModel: NotificationsViewModel
    let router: Router<SettingsRoute>
    @State private var isShowingConsent = false
    @State private var projectQuery = ""
    /// Mirrors `viewModel.isSyncing`, but only after it's been true for
    /// `syncIndicatorDelay` — see `body`'s `.task(id:)`. A round trip that
    /// finishes faster than that never shows anything, so a quick toggle
    /// doesn't flash a spinner on and immediately back off.
    @State private var showSyncIndicator = false
    @Environment(\.openURL) private var openURL

    private static let syncIndicatorDelay: Duration = .seconds(1)

    /// `viewModel` is built once by `SettingsRootView`'s cache and handed
    /// down (see `NotificationsViewModelCache`), not via a factory held in
    /// `@State` here — `ProjectNotificationsView` needs the exact same
    /// instance so a project's event selection shows up back on this list
    /// without a reload, and only the caller that already stabilizes it
    /// across `.navigationDestination` re-invocations can guarantee that.
    init(viewModel: NotificationsViewModel, router: Router<SettingsRoute>) {
        self.viewModel = viewModel
        self.router = router
    }

    /// `viewModel.projects` (a flat array) reordered so each project is
    /// immediately followed by its own children, recursively, with `depth`
    /// tracking how many ancestors it has — `ProjectNotificationRow` uses
    /// that to indent subprojects instead of showing everything flat.
    private var orderedProjects: [(project: Project, depth: Int)] {
        let byParent = Dictionary(grouping: viewModel.projects, by: \.parentProjectID)
        var result: [(project: Project, depth: Int)] = []
        func append(parentID: Int?, depth: Int) {
            let children = (byParent[parentID] ?? []).sorted { $0.position < $1.position }
            for child in children {
                result.append((child, depth))
                append(parentID: child.id, depth: depth + 1)
            }
        }
        append(parentID: nil, depth: 0)
        return result
    }

    private var filteredProjects: [(project: Project, depth: Int)] {
        guard !projectQuery.isEmpty else { return orderedProjects }
        return orderedProjects.filter { $0.project.title.localizedCaseInsensitiveContains(projectQuery) }
    }

    /// How many projects currently have at least one event selected — a
    /// project can be present in `settings.projectEvents` with an empty set
    /// (its webhook was just torn down but the key wasn't removed), so this
    /// can't just count that dictionary's keys.
    private var connectedProjectCount: Int {
        viewModel.projects.count { !viewModel.settings.events(for: $0.id).isEmpty }
    }

    var body: some View {
        content
            .background(VikuColor.Surface.page)
            .navigationTitle(Text("Notifications", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $isShowingConsent) {
                NotificationsConsentSheet {
                    Task { await viewModel.confirmEnable() }
                }
            }
            .onAppear { Task { await viewModel.load() } }
            // `.task(id:)` cancels the previous task the instant `isSyncing`
            // changes, so a sync that finishes within `syncIndicatorDelay`
            // never reaches the `withAnimation` below at all.
            .task(id: viewModel.isSyncing) {
                if viewModel.isSyncing {
                    try? await Task.sleep(for: Self.syncIndicatorDelay)
                    guard !Task.isCancelled else { return }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSyncIndicator = viewModel.isSyncing
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, VikuSpacing.xxl)
        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Couldn't load projects", bundle: .module),
                message: message,
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, VikuSpacing.xxl)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    enableSection
                    if viewModel.settings.isEnabled {
                        userLevelSection
                        projectsSection
                    }
                    // Keeps the last card clear of the tab bar.
                    Color.clear.frame(height: VikuSpacing.xxl)
                }
            }
            .searchable(
                text: $projectQuery,
                placement: .automatic,
                prompt: Text("Search projects...", bundle: .module),
            )
        }
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Toggle(isOn: enabledBinding) {
                        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                            Text("Push Notifications", bundle: .module)
                            Text("Via Viku Relay", bundle: .module)
                                .font(VikuFont.footnote)
                                .foregroundStyle(VikuColor.textSecondary)
                        }
                    }
                    .disabled(viewModel.pendingChange == .enabling || viewModel.pendingChange == .disabling)
                }
                .padding(.vertical, VikuSpacing.xs)

                if viewModel.settings.isEnabled, let relayTargetURL = viewModel.relayTargetURL {
                    Divider()
                    HStack(spacing: VikuSpacing.sm) {
                        Circle()
                            .fill(VikuColor.Semantic.success)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "Registered with \(relayTargetURL.host ?? relayTargetURL.absoluteString)", bundle: .module))
                            .font(VikuFont.footnote)
                            .foregroundStyle(VikuColor.textSecondary)
                    }
                    .padding(.vertical, VikuSpacing.sm)
                }

                if showSyncIndicator {
                    Divider()
                    syncingRow
                        .padding(.vertical, VikuSpacing.sm)
                        .transition(.opacity)
                }
            }
            .vikuCardRow(index: 0, count: 1)

            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                Group {
                    if viewModel.settings.isEnabled {
                        Text("Turning this off removes the webhooks Viku created on your instance.", bundle: .module)
                    } else {
                        Text("Requires Viku Relay, a service hosted by the Viku team.", bundle: .module)
                            + Text(verbatim: " ")
                            + Text("Vikunja does not send push to iOS directly.", bundle: .module)
                    }
                }
                .font(VikuFont.caption)
                .foregroundStyle(VikuColor.textTertiary)

                if viewModel.isPermissionDenied {
                    deniedBanner
                }
            }
            .padding(.horizontal, VikuSpacing.md)
        }
        .padding(.top, VikuSpacing.sm)
    }

    /// Shown once `confirmEnable()`/`disable()`/a toggle's sync has been
    /// running for longer than `syncIndicatorDelay` — a fast round trip
    /// never reaches this, so the screen doesn't flash a spinner for
    /// something that was over almost instantly.
    private var syncingRow: some View {
        HStack(spacing: VikuSpacing.sm) {
            ProgressView()
            Text("Setting up notifications…", bundle: .module)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Notifications are turned off for Viku in iOS Settings.", bundle: .module)
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Button(String(localized: "Open Settings", bundle: .module)) {
                openSystemSettings()
            }
        }
    }

    /// Whether the "Overdue Tasks" webhook event is selected — the time row
    /// only means something once this app is actually subscribed to it.
    private var showsOverdueTasksTimeRow: Bool {
        viewModel.settings.userLevelEvents.contains(.taskOverdue)
    }

    private var userLevelRowCount: Int {
        WebhookEvent.userDirectedOrdered.count + (showsOverdueTasksTimeRow ? 1 : 0)
    }

    private var userLevelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader {
                Text("User Notifications", bundle: .module)
                    .vikuSectionHeader()
            }
            VStack(spacing: 0) {
                ForEach(Array(WebhookEvent.userDirectedOrdered.enumerated()), id: \.element) { index, event in
                    Toggle(isOn: userLevelEventBinding(event)) {
                        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                            Text(eventLabel(event))
                            Text(verbatim: event.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(VikuColor.textTertiary)
                        }
                    }
                    .disabled(viewModel.pendingChange == .userLevel)
                    .vikuCardRow(index: index, count: userLevelRowCount)
                }
                if showsOverdueTasksTimeRow {
                    overdueTasksRemindersTimeRow
                        .vikuCardRow(index: WebhookEvent.userDirectedOrdered.count, count: userLevelRowCount)
                }
            }
        }
    }

    private var overdueTasksRemindersTimeRow: some View {
        DatePicker(
            selection: overdueTasksRemindersTimeBinding,
            displayedComponents: .hourAndMinute,
        ) {
            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text("Fires Daily At", bundle: .module)
                Text(accountTimezoneLabel)
                    .font(VikuFont.footnote)
                    .foregroundStyle(VikuColor.textSecondary)
            }
        }
    }

    /// Clarifies which clock "Fires Daily At" is in — Vikunja evaluates that
    /// time against the user's account-wide time zone (`User.timezone`, the
    /// same one used for every other reminder, not something specific to
    /// overdue tasks), not this device's, so a bare "9:00" would otherwise
    /// read as local time when it might not be. Falls back to a zone-less
    /// note when the user hasn't set one on the server (it then uses the
    /// server's own default).
    private var accountTimezoneLabel: String {
        if let timezone = viewModel.accountTimezone {
            String(localized: "In \(timezone)", bundle: .module)
        } else {
            String(localized: "In your Vikunja account's time zone", bundle: .module)
        }
    }

    private var overdueTasksRemindersTimeBinding: Binding<Date> {
        Binding(
            get: { Self.date(fromTime: viewModel.overdueTasksRemindersTime) },
            set: { newDate in
                let time = Self.timeString(from: newDate)
                Task { await viewModel.setOverdueTasksRemindersTime(time) }
            },
        )
    }

    /// Parses Vikunja's `HH:mm` wire format into a `Date` carrying just
    /// those hour/minute components (on today's date — `DatePicker`'s
    /// `.hourAndMinute` display ignores the rest). Tolerant of an unpadded
    /// hour (`"9:00"`), which some server responses use.
    private static func date(fromTime time: String) -> Date {
        let parts = time.split(separator: ":")
        let hour = parts.first.flatMap { Int($0) } ?? 9
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    /// Formats a `DatePicker` selection back into Vikunja's `HH:mm` wire
    /// format, zero-padded — required by the server's `"15:04"` time parse.
    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
    }

    @ViewBuilder
    private var projectsSection: some View {
        if !viewModel.projects.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Project Notifications", bundle: .module)
                            .vikuSectionHeader()
                        Spacer()
                        Text(verbatim: "\(connectedProjectCount)")
                            .font(VikuFont.footnote)
                            .foregroundStyle(VikuColor.textTertiary)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(filteredProjects.enumerated()), id: \.element.project.id) { index, entry in
                        Button {
                            router.push(.projectNotifications(entry.project))
                        } label: {
                            ProjectNotificationRow(
                                viewModel: viewModel,
                                project: entry.project,
                                depth: entry.depth,
                                eventCount: viewModel.settings.events(for: entry.project.id).count,
                            )
                        }
                        .buttonStyle(.plain)
                        .vikuCardRow(index: index, count: filteredProjects.count)
                    }
                }
            }
        }
    }

    /// The shared padding recipe for a plain section header above a card —
    /// mirrors `ProjectOverviewView`'s own section headers (flush with the
    /// nav title horizontally, a bit more breathing room above than below).
    private func sectionHeader(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md + VikuSpacing.xs)
            .padding(.bottom, VikuSpacing.sm)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.isEnabled },
            set: { newValue in
                if newValue {
                    isShowingConsent = true
                } else {
                    Task { await viewModel.disable() }
                }
            },
        )
    }

    private func userLevelEventBinding(_ event: WebhookEvent) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.userLevelEvents.contains(event) },
            set: { newValue in Task { await viewModel.setUserLevelEvent(event, isEnabled: newValue) } },
        )
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }
}

/// Display name for an individual webhook event — shared by `NotificationsView`'s
/// user-level toggles and `ProjectNotificationsView`'s per-project checkbox list.
func eventLabel(_ event: WebhookEvent) -> String {
    switch event {
    case .taskCreated: String(localized: "Task Created", bundle: .module)
    case .taskUpdated: String(localized: "Task Updated", bundle: .module)
    case .taskDeleted: String(localized: "Task Deleted", bundle: .module)
    case .taskAssigneeCreated: String(localized: "Task Assigned", bundle: .module)
    case .taskAssigneeDeleted: String(localized: "Task Unassigned", bundle: .module)
    case .taskCommentCreated: String(localized: "Comment Added", bundle: .module)
    case .taskCommentEdited: String(localized: "Comment Edited", bundle: .module)
    case .taskCommentDeleted: String(localized: "Comment Deleted", bundle: .module)
    case .taskAttachmentCreated: String(localized: "Attachment Added", bundle: .module)
    case .taskAttachmentDeleted: String(localized: "Attachment Removed", bundle: .module)
    case .taskRelationCreated: String(localized: "Task Relation Added", bundle: .module)
    case .taskRelationDeleted: String(localized: "Task Relation Removed", bundle: .module)
    case .projectUpdated: String(localized: "Project Updated", bundle: .module)
    case .projectDeleted: String(localized: "Project Deleted", bundle: .module)
    case .projectSharedUser: String(localized: "Project Shared with a User", bundle: .module)
    case .projectSharedTeam: String(localized: "Project Shared with a Team", bundle: .module)
    case .taskOverdue: String(localized: "Overdue Tasks", bundle: .module)
    case .taskReminderFired: String(localized: "Reminders", bundle: .module)
    }
}

/// One row in the project search list: a color swatch (indented by `depth`
/// for a subproject), the project's name and its count of third-party
/// webhooks (if any), and either a bell badge showing how many events are
/// selected or a plain "Not Connected" label when none are.
private struct ProjectNotificationRow: View {
    let viewModel: NotificationsViewModel
    let project: Project
    let depth: Int
    let eventCount: Int

    /// Fetched lazily via `.task` once this row appears — see
    /// `NotificationsViewModel.otherWebhooks(for:)`. Not loaded eagerly for
    /// every project up front, only for rows the list actually renders.
    @State private var otherWebhookCount = 0

    private var swatchColor: Color {
        Color(vikuHex: project.hexColor) ?? VikuColor.brandPrimary
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatchColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text(project.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if otherWebhookCount > 0 {
                    Text(String(localized: "\(otherWebhookCount) third-party webhooks", bundle: .module))
                        .font(VikuFont.caption)
                        .foregroundStyle(VikuColor.textTertiary)
                }
            }

            Spacer(minLength: VikuSpacing.sm)

            if eventCount > 0 {
                HStack(spacing: VikuSpacing.xxs) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(verbatim: "\(eventCount)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(VikuColor.brandPrimary)
                .padding(.horizontal, VikuSpacing.sm)
                .padding(.vertical, VikuSpacing.xxs)
                .background(Capsule().fill(VikuColor.brandPrimary.opacity(0.12)))
            } else {
                Text("Not Connected", bundle: .module)
                    .font(VikuFont.footnote)
                    .foregroundStyle(VikuColor.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VikuColor.textTertiary)
        }
        .padding(.vertical, VikuSpacing.xs)
        .padding(.leading, CGFloat(depth) * (VikuSpacing.md + VikuSpacing.xxs))
        .task(id: project.id) {
            otherWebhookCount = await viewModel.otherWebhooks(for: project.id).count
        }
    }
}
