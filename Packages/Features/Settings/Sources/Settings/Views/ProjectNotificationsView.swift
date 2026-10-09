import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// One project's own webhook: which events notify this device, reached by
/// tapping a project row on `NotificationsView`. Shares the same
/// `NotificationsViewModel` instance as that list (see
/// `SettingsRootView.notificationsViewModelCache`) so a change here shows up
/// back there without a reload, and every toggle applies and syncs
/// immediately — there's no separate "save" step.
struct ProjectNotificationsView: View {
    let viewModel: NotificationsViewModel
    let project: Project

    @State private var otherWebhooks: [Webhook] = []
    @State private var isShowingDisconnectConfirmation = false

    /// The curated subset of `WebhookEvent.projectOrdered` this screen
    /// exposes, grouped for display — deliberately narrower than "every
    /// event the server would accept" (see the design reference this
    /// screen matches). `taskReminderFired` belongs here despite being in
    /// `WebhookEvent.userDirected`: that set only restricts what a
    /// *user*-level webhook may use, not a project one — see its doc
    /// comment in `WebhookEvent.swift`.
    private static let eventGroups: [(title: String, events: [WebhookEvent])] = [
        (
            String(localized: "Reminders", bundle: .module),
            [.taskReminderFired],
        ),
        (
            String(localized: "Tasks", bundle: .module),
            [.taskCreated, .taskUpdated, .taskDeleted, .taskAssigneeCreated],
        ),
        (
            String(localized: "Collaboration", bundle: .module),
            [.taskCommentCreated, .taskAttachmentCreated, .projectSharedUser],
        ),
    ]

    /// Every event this screen exposes across all of `eventGroups` — what
    /// the "All" preset selects, rather than `WebhookEvent.projectOrdered`
    /// (which includes events this screen deliberately doesn't show).
    private static let allExposedEvents = Set(eventGroups.flatMap(\.events))

    private static let recommendedEvents: Set<WebhookEvent> = [
        .taskReminderFired, .taskAssigneeCreated, .taskCommentCreated,
    ]

    private var selectedEvents: Set<WebhookEvent> {
        viewModel.settings.events(for: project.id)
    }

    private var isDisabled: Bool {
        viewModel.pendingChange == .project(project.id)
    }

    private var swatchColor: Color {
        Color(vikuHex: project.hexColor) ?? VikuColor.brandPrimary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                infoSection
                presetsSection
                eventGroupSections
                if !otherWebhooks.isEmpty {
                    otherWebhooksSection
                }
                if !selectedEvents.isEmpty {
                    disconnectSection
                }
                // Keeps the last card clear of the tab bar.
                Color.clear.frame(height: VikuSpacing.xxl)
            }
        }
        .background(VikuColor.Surface.page)
        .navigationTitle(project.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            otherWebhooks = await viewModel.otherWebhooks(for: project.id)
        }
        .confirmationDialog(
            Text("Disconnect this project's webhook?", bundle: .module),
            isPresented: $isShowingDisconnectConfirmation,
            titleVisibility: .visible,
        ) {
            Button(String(localized: "Disconnect Webhook", bundle: .module), role: .destructive) {
                Task { await viewModel.disableProjectWebhook(project) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VikuSpacing.sm) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(swatchColor)
                    .frame(width: 10, height: 10)
                Text(project.title)
                    .font(VikuFont.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.sm)
            .padding(.bottom, VikuSpacing.sm)

            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                infoRow(
                    label: String(localized: "Destination", bundle: .module),
                    value: viewModel.relayTargetURL.map(maskedTarget) ?? "—",
                    monospaced: true,
                )
                infoRow(
                    label: String(localized: "Signature", bundle: .module),
                    value: String(localized: "HMAC secret generated", bundle: .module),
                )
                infoRow(
                    label: String(localized: "Status", bundle: .module),
                    value: selectedEvents.isEmpty
                        ? String(localized: "Not Connected", bundle: .module)
                        : String(localized: "Connected", bundle: .module),
                    valueColor: selectedEvents.isEmpty ? VikuColor.textSecondary : VikuColor.Semantic.success,
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, VikuSpacing.xs)
            .vikuCardRow(index: 0, count: 1)
        }
    }

    private func infoRow(
        label: String,
        value: String,
        valueColor: Color = VikuColor.textSecondary,
        monospaced: Bool = false,
    ) -> some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm) {
            Text(verbatim: label)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(verbatim: value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : VikuFont.footnote)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            HStack(alignment: .lastTextBaseline) {
                // Deliberately not `.vikuSectionHeader()` — that's the small,
                // muted, all-caps style used for the group headers below
                // (Reminders/Tasks/Collaboration), which read as nested
                // *under* this one. This title needs to outrank them.
                Text("Events That Notify You", bundle: .module)
                    .font(VikuFont.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Text(verbatim: "\(selectedEvents.count)")
                    .font(VikuFont.footnote)
                    .foregroundStyle(VikuColor.textTertiary)
            }
            HStack(spacing: VikuSpacing.sm) {
                presetChip(String(localized: "Recommended", bundle: .module), events: Self.recommendedEvents)
                presetChip(String(localized: "All", bundle: .module), events: Self.allExposedEvents)
                presetChip(String(localized: "None", bundle: .module), events: [])
            }
        }
        .padding(.horizontal, VikuSpacing.md)
        .padding(.top, VikuSpacing.md + VikuSpacing.xs)
    }

    private func presetChip(_ title: String, events: Set<WebhookEvent>) -> some View {
        let isSelected = selectedEvents == events
        return Button {
            Task { await viewModel.setProjectEvents(events, for: project) }
        } label: {
            Text(verbatim: title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm - VikuSpacing.xxs)
                .foregroundStyle(isSelected ? Color.white : VikuColor.textSecondary)
                .background(Capsule().fill(isSelected ? VikuColor.brandPrimary : VikuColor.Surface.field))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                                Text(eventLabel(event))
                                Text(verbatim: event.rawValue)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(VikuColor.textTertiary)
                            }
                        }
                        .disabled(isDisabled)
                        .vikuCardRow(index: index, count: group.events.count)
                    }
                }
            }
        }
    }

    private var otherWebhooksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Other Webhooks on This Project", bundle: .module)
                .vikuSectionHeader()
                .padding(.horizontal, VikuSpacing.md)
                .padding(.top, VikuSpacing.md + VikuSpacing.xs)
                .padding(.bottom, VikuSpacing.sm)

            VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                ForEach(otherWebhooks) { webhook in
                    HStack(alignment: .top, spacing: VikuSpacing.sm) {
                        Image(systemName: "link")
                            .font(.system(size: 13))
                            .foregroundStyle(VikuColor.textTertiary)
                        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                            Text(verbatim: webhook.targetURL.absoluteString)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(
                                String(
                                    localized: "\(webhook.events.count) events · created outside Viku · read-only",
                                    bundle: .module,
                                ),
                            )
                            .font(VikuFont.caption)
                            .foregroundStyle(VikuColor.textTertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, VikuSpacing.xs)
            .vikuCardRow(index: 0, count: 1)
        }
    }

    private var disconnectSection: some View {
        Button(role: .destructive) {
            isShowingDisconnectConfirmation = true
        } label: {
            Text("Disconnect Webhook", bundle: .module)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, VikuSpacing.xs)
        }
        .disabled(isDisabled)
        .vikuCardRow(index: 0, count: 1)
        .padding(.top, VikuSpacing.md)
    }

    private func eventBinding(_ event: WebhookEvent) -> Binding<Bool> {
        Binding(
            get: { selectedEvents.contains(event) },
            set: { newValue in Task { await viewModel.setProjectEvent(event, isEnabled: newValue, for: project) } },
        )
    }

    /// Host plus a masked last path segment, e.g.
    /// `relay.viku.dev/••••ce-1` — this device's relay URL embeds an opaque
    /// id (see `PushRegistration`), so only a sliver of it is shown rather
    /// than the whole thing.
    private func maskedTarget(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let last = url.lastPathComponent
        guard last.count > 4 else { return host }
        return "\(host)/••••\(last.suffix(4))"
    }
}
