import SwiftUI
import VikuDesignSystem

/// The consent modal shown before the OS permission prompt. `onAgree` runs
/// `NotificationsViewModel.confirmEnable()`, which is what actually
/// triggers the system authorization request. A plain bottom sheet (no
/// `NavigationStack`/toolbar) with an acknowledgement checkbox that gates
/// the primary button — the person has to actively confirm they understand
/// what Viku Relay is before the OS permission prompt even appears.
struct NotificationsConsentSheet: View {
    let onAgree: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasAcknowledged = false

    private struct Point {
        let systemImage: String
        let title: String
        let body: String
    }

    private var points: [Point] {
        [
            Point(
                systemImage: "server.rack",
                title: String(localized: "Hosted by the Viku team", bundle: .module),
                body: String(
                    localized: """
                    Viku Relay receives your instance's webhooks and forwards them to your iPhone \
                    through Apple Push Notification service. It is not self-hosted: APNs requires \
                    Apple credentials that only the Viku team holds.
                    """,
                    bundle: .module,
                ),
            ),
            Point(
                systemImage: "eye",
                title: String(localized: "What data goes through the relay", bundle: .module),
                body: String(
                    localized: """
                    The event type, the task title, and the project name. Your token or password \
                    never leaves the device. The webhook signing secret is shared with the relay \
                    so it can verify deliveries.
                    """,
                    bundle: .module,
                ),
            ),
            Point(
                systemImage: "globe",
                title: String(localized: "Your instance needs internet access", bundle: .module),
                body: String(localized: "Vikunja has to reach relay.viku.dev over HTTPS.", bundle: .module),
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.lg) {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
                            .fill(VikuColor.brandPrimary)
                            .frame(width: 52, height: 52)
                        Image(systemName: "bell.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("Enable push notifications", bundle: .module)
                        .font(VikuFont.title2)
                        .fontWeight(.bold)

                    (
                        Text("Vikunja cannot send notifications to iOS by itself.", bundle: .module)
                            + Text(verbatim: " ")
                            + Text(
                                "To receive them, Viku connects your instance's webhooks to an intermediary service.",
                                bundle: .module,
                            )
                    )
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: VikuSpacing.md) {
                    ForEach(points, id: \.title) { point in
                        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                            RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xs, style: .continuous)
                                .fill(VikuColor.Surface.field)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Image(systemName: point.systemImage)
                                        .font(.system(size: 14))
                                        .foregroundStyle(VikuColor.textSecondary)
                                }
                            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                                Text(verbatim: point.title)
                                    .font(VikuFont.subheadline)
                                    .fontWeight(.semibold)
                                Text(verbatim: point.body)
                                    .font(VikuFont.footnote)
                                    .foregroundStyle(VikuColor.textSecondary)
                            }
                        }
                    }
                }

                acknowledgementRow
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.xl)
            .padding(.bottom, VikuSpacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: VikuSpacing.sm + VikuSpacing.xs) {
                Button {
                    onAgree()
                    dismiss()
                } label: {
                    Text("Agree & Continue", bundle: .module)
                        .font(VikuFont.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasAcknowledged)

                Button(String(localized: "Not Now", bundle: .module)) { dismiss() }
                    .font(VikuFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(VikuColor.textSecondary)
            }
            .padding(VikuSpacing.md)
            .background(VikuColor.Surface.page)
        }
        .presentationDragIndicator(.visible)
    }

    private var acknowledgementRow: some View {
        Button {
            hasAcknowledged.toggle()
        } label: {
            HStack(alignment: .top, spacing: VikuSpacing.sm) {
                Image(systemName: hasAcknowledged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(hasAcknowledged ? VikuColor.brandPrimary : VikuColor.textTertiary)
                Text(
                    "I understand my events will pass through Viku Relay, a service operated by the Viku team.",
                    bundle: .module,
                )
                .font(VikuFont.footnote)
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
