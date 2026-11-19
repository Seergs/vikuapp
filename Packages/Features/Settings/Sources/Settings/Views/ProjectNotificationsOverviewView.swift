import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

/// The project's notification settings entry point, available offline.
/// Preset and detail rows are placeholders; event changes remain in Customize.
struct ProjectNotificationsOverviewView: View {
    let project: Project
    let router: AppRouter

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications for what other people do in this project", bundle: .module)
                    .font(VikuFont.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md)
                sectionHeader(String(localized: "Notify Me About", bundle: .module))
                VStack(spacing: 0) {
                    optionRow(
                        title: String(localized: "Disabled", bundle: .module),
                        subtitle: String(localized: "This project won't send you notifications.", bundle: .module),
                    )
                    .vikuCardRow(index: 0, count: 3)
                    optionRow(
                        title: String(localized: "Recommended", bundle: .module),
                        subtitle: String(localized: "Assignments and new comments in the project.", bundle: .module),
                    )
                    .vikuCardRow(index: 1, count: 3)
                    Button {
                        router.push(SettingsRoute.projectNotificationEvents(project))
                    } label: {
                        HStack(spacing: VikuSpacing.sm) {
                            optionRow(
                                title: String(localized: "Customize…", bundle: .module),
                                subtitle: String(localized: "Choose another type", bundle: .module),
                            )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(VikuFont.footnote)
                                .foregroundStyle(palette.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .vikuCardRow(index: 2, count: 3)
                }

                sectionHeader(String(localized: "More", bundle: .module))
                optionRow(title: String(localized: "More Details", bundle: .module))
                    .vikuCardRow(index: 0, count: 1)
            }
            .padding(.bottom, VikuSpacing.xxl)
        }
        .background(palette.pageBackground)
        .navigationTitle(Text(verbatim: project.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
