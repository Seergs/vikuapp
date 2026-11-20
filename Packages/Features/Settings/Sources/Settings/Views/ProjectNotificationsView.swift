import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// One project's own webhook: which events notify this device, reached by
/// choosing "Customize" on `ProjectNotificationsOverviewView`. Shares the same
/// `NotificationsViewModel` instance as the overview and main project list (see
/// `SettingsRootView.notificationsViewModelCache`) so a change here shows up
/// back there without a reload, and every toggle applies and syncs
/// immediately — there's no separate "save" step.
struct ProjectNotificationsView: View {
    let viewModel: NotificationsViewModel
    let project: Project

    @Environment(\.vikuPalette) private var palette

    /// Not reachable until Projects' own offline-create path exists — a
    /// project without a synced id yet can't have webhook settings.
    private var resolvedProjectID: Int? {
        project.id.remoteValue
    }

    private var selectedEvents: Set<WebhookEvent> {
        resolvedProjectID.map { viewModel.settings.events(for: $0) } ?? []
    }

    private var isDisabled: Bool {
        viewModel.isSyncing || viewModel.isLoading || resolvedProjectID == nil
            || (viewModel.isVerifyingRegistration && viewModel.relayTargetURL == nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: project.title)
                    .font(VikuFont.headline)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md)
                    .accessibilityAddTraits(.isHeader)
                taskNotificationsSection
                projectNotificationsSection
                // Keeps the last card clear of the tab bar.
                Color.clear.frame(height: VikuSpacing.xxl)
            }
        }
        .background(palette.pageBackground)
        .navigationTitle(Text("Notifications", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var taskNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "Task Notifications", bundle: .module))
            VStack(spacing: 0) {
                assignmentsRow
                    .vikuCardRow(index: 0, count: 5)
                eventToggle(.taskCommentCreated, title: String(localized: "New Comments", bundle: .module))
                    .vikuCardRow(index: 1, count: 5)
                eventToggle(.taskAttachmentCreated, title: String(localized: "New Attachments", bundle: .module))
                    .vikuCardRow(index: 2, count: 5)
                eventToggle(.taskCreated, title: String(localized: "New Tasks", bundle: .module))
                    .vikuCardRow(index: 3, count: 5)
                eventToggle(.taskDeleted, title: String(localized: "Deleted Tasks", bundle: .module))
                    .vikuCardRow(index: 4, count: 5)
            }
            Text("Comments, attachments, and changes are notified for any task in this project.", bundle: .module)
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, VikuSpacing.md)
                .padding(.top, VikuSpacing.sm)
        }
    }

    private var projectNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "Project Notifications", bundle: .module))
            eventToggle(
                .projectSharedUser,
                title: String(localized: "New Access", bundle: .module),
                subtitle: String(localized: "When the project is shared with a person or team.", bundle: .module),
            )
            .vikuCardRow(index: 0, count: 1)
        }
    }

    private var assignmentsRow: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
            Menu {
                Picker(selection: assignmentBinding) {
                    ForEach(ProjectAssignmentSelection.allCases, id: \.self) { selection in
                        Text(verbatim: selection.title).tag(selection)
                    }
                } label: {
                    Text("Assignments", bundle: .module)
                }
            } label: {
                HStack(spacing: VikuSpacing.sm) {
                    Text("Assignments", bundle: .module)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: VikuSpacing.sm)
                    Text(verbatim: viewModel.assignmentSelection(for: project).title)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityHidden(true)
                }
                .font(VikuFont.body)
                .padding(.vertical, VikuSpacing.sm)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .notificationControlsDisabled(isDisabled)
            savingProgress(for: .taskAssigneeCreated)
        }
    }

    private var assignmentBinding: Binding<ProjectAssignmentSelection> {
        Binding(
            get: { viewModel.assignmentSelection(for: project) },
            set: { selection in
                Task { await viewModel.selectAssignments(selection, for: project) }
            },
        )
    }

    private func eventToggle(_ event: WebhookEvent, title: String, subtitle: String? = nil) -> some View {
        Toggle(isOn: eventBinding(event)) {
            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text(verbatim: title)
                    .font(VikuFont.body)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                savingProgress(for: event)
            }
        }
        .notificationControlsDisabled(isDisabled)
        .padding(.vertical, VikuSpacing.xs)
    }

    private func savingProgress(for event: WebhookEvent) -> some View {
        NotificationProgressView(
            isActive: resolvedProjectID.map { viewModel.pendingChange == .project($0) } == true
                && viewModel.pendingEvent == event,
            title: String(localized: "Saving…", bundle: .module),
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(verbatim: title)
            .vikuSectionHeader()
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md + VikuSpacing.xs)
            .padding(.bottom, VikuSpacing.sm)
    }

    private func eventBinding(_ event: WebhookEvent) -> Binding<Bool> {
        Binding(
            get: {
                event == .projectSharedUser
                    ? viewModel.isProjectSharingEnabled(for: project)
                    : selectedEvents.contains(event)
            },
            set: { newValue in
                Task {
                    if event == .projectSharedUser {
                        await viewModel.setProjectSharingEnabled(newValue, for: project)
                    } else {
                        await viewModel.setProjectEvent(event, isEnabled: newValue, for: project)
                    }
                }
            },
        )
    }
}
