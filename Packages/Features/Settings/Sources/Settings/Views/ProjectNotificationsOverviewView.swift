import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

/// Reflects saved events and applies project notification presets.
/// Reads are local; webhook changes require a reachable server.
struct ProjectNotificationsOverviewView: View {
    let viewModel: NotificationsViewModel
    let project: Project
    let router: AppRouter

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: project.title)
                    .font(VikuFont.headline)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md)
                    .accessibilityAddTraits(.isHeader)
                Text("Notifications for what other people do in this project", bundle: .module)
                    .font(VikuFont.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.sm)
                sectionHeader(String(localized: "Notify Me About", bundle: .module))
                VStack(spacing: 0) {
                    presetButton(
                        .disabled,
                        title: String(localized: "Disabled", bundle: .module),
                        subtitle: String(localized: "This project won't send you notifications.", bundle: .module),
                    )
                    .vikuCardRow(index: 0, count: 3)
                    presetButton(
                        .recommended,
                        title: String(localized: "Recommended", bundle: .module),
                        subtitle: String(localized: "When tasks are assigned to you.", bundle: .module),
                    )
                    .vikuCardRow(index: 1, count: 3)
                    presetButton(
                        .custom,
                        title: String(localized: "Customize…", bundle: .module),
                        subtitle: String(localized: "Choose another type", bundle: .module),
                    )
                    .vikuCardRow(index: 2, count: 3)
                }

                NotificationProgressView(
                    isActive: viewModel.isSyncing,
                    title: String(localized: "Updating notifications…", bundle: .module),
                )
                .padding(.horizontal, VikuSpacing.md)
                Text("Changing these settings requires a connection to your Vikunja server.", bundle: .module)
                    .font(VikuFont.caption)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.sm)

                sectionHeader(String(localized: "More", bundle: .module))
                Button {
                    router.push(SettingsRoute.projectNotificationDetails(project))
                } label: {
                    HStack(spacing: VikuSpacing.sm) {
                        optionRow(title: String(localized: "More Details", bundle: .module))
                        chevron
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .vikuCardRow(index: 0, count: 1)
            }
            .padding(.bottom, VikuSpacing.xxl)
        }
        .background(palette.pageBackground)
        .navigationTitle(Text("Notifications", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(VikuFont.footnote)
            .foregroundStyle(palette.textTertiary)
            .accessibilityHidden(true)
    }

    private func presetButton(_ preset: ProjectNotificationPreset, title: String, subtitle: String) -> some View {
        let isSelected = viewModel.projectNotificationPreset(for: project) == preset
        return Button {
            if preset == .custom {
                router.push(SettingsRoute.projectNotificationEvents(project))
            } else {
                Task { await viewModel.selectProjectNotificationPreset(preset, for: project) }
            }
        } label: {
            HStack(spacing: VikuSpacing.sm) {
                optionRow(title: title, subtitle: subtitle)
                Image(systemName: "checkmark")
                    .font(VikuFont.body.weight(.semibold))
                    .foregroundStyle(palette.brand)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                if preset == .custom {
                    chevron
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .notificationControlsDisabled(viewModel.isSyncing || viewModel.isLoading || project.id.remoteValue == nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(verbatim: title)
            .vikuSectionHeader()
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md + VikuSpacing.xs)
            .padding(.bottom, VikuSpacing.sm)
    }

    private func optionRow(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
            Text(verbatim: title)
                .font(VikuFont.body)
                .foregroundStyle(palette.textPrimary)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(VikuFont.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VikuSpacing.sm)
    }
}
