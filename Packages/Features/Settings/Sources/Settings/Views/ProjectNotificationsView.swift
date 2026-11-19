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

    /// Project events grouped by the activity the user wants to follow.
    private static let eventGroups: [(title: String, events: [WebhookEvent])] = [
        (
            String(localized: "People and Conversation", bundle: .module),
            [.taskAssigneeCreated, .taskCommentCreated, .taskAttachmentCreated],
        ),
        (
            String(localized: "Task Changes", bundle: .module),
            [.taskCreated, .taskUpdated, .taskDeleted],
        ),
        (
            String(localized: "Project Access", bundle: .module),
            [.projectSharedUser],
        ),
    ]

    /// Not reachable until Projects' own offline-create path exists — a
    /// project without a synced id yet can't have webhook settings.
    private var resolvedProjectID: Int? {
        project.id.remoteValue
    }

    private var selectedEvents: Set<WebhookEvent> {
        resolvedProjectID.map { viewModel.settings.events(for: $0) } ?? []
    }

    private var isDisabled: Bool {
        resolvedProjectID.map { viewModel.pendingChange == .project($0) } ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                eventGroupSections
                // Keeps the last card clear of the tab bar.
                Color.clear.frame(height: VikuSpacing.xxl)
            }
        }
        .background(palette.pageBackground)
        .navigationTitle(Text(verbatim: project.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var eventGroupSections: some View {
        ForEach(Array(Self.eventGroups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: group.title)
                    .vikuSectionHeader()
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md + VikuSpacing.xs)
                    .padding(.bottom, VikuSpacing.sm)

                VStack(spacing: 0) {
                    ForEach(Array(group.events.enumerated()), id: \.element) { index, event in
                        Toggle(isOn: eventBinding(event)) {
                            if event == .projectSharedUser {
                                VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                                    Text("Project Shared", bundle: .module)
                                    Text("When shared with another person or team", bundle: .module)
                                        .font(VikuFont.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            } else {
                                Text(verbatim: eventLabel(event))
                            }
                        }
                        .disabled(isDisabled)
                        .padding(.vertical, VikuSpacing.xs)
                        .vikuCardRow(index: index, count: group.events.count)
                    }
                }
            }
        }
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
