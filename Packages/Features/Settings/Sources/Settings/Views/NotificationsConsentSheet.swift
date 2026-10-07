import SwiftUI
import VikuDesignSystem

/// The consent modal shown before the OS permission prompt. `onAgree` runs
/// `NotificationsViewModel.confirmEnable()`, which is what actually
/// triggers the system authorization request.
struct NotificationsConsentSheet: View {
    let onAgree: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VikuSpacing.lg) {
                    VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                        Text("Vikunja cannot send notifications to iOS by itself.", bundle: .module)
                        Text(
                            "To receive them, Viku connects your instance's webhooks to an intermediary service.",
                            bundle: .module,
                        )
                    }
                    .font(VikuFont.body)

                    section(
                        title: String(localized: "Hosted by the Viku team", bundle: .module),
                        body: String(
                            localized: """
                            Viku Relay receives your instance's webhooks and forwards them to your iPhone \
                            through Apple Push Notification service. It is not self-hosted: APNs requires \
                            Apple credentials that only the Viku team holds.
                            """,
                            bundle: .module,
                        ),
                    )

                    section(
                        title: String(localized: "What data goes through the relay", bundle: .module),
                        body: String(
                            localized: """
                            The event type, the task title, and the project name. Your token or password \
                            never leaves the device. The webhook signing secret is shared with the relay \
                            so it can verify deliveries.
                            """,
                            bundle: .module,
                        ),
                    )

                    section(
                        title: String(localized: "Your instance needs internet access", bundle: .module),
                        body: String(
                            localized: "Vikunja has to reach relay.viku.dev over HTTPS.",
                            bundle: .module,
                        ),
                    )
                }
                .padding(VikuSpacing.md)
            }
            .navigationTitle(Text("Enable push notifications", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: VikuSpacing.sm) {
                    Text(
                        "I understand my events will pass through Viku Relay, a service operated by the Viku team.",
                        bundle: .module,
                    )
                    .font(VikuFont.footnote)
                    .foregroundStyle(VikuColor.textSecondary)

                    Button(String(localized: "Agree & Continue", bundle: .module)) {
                        onAgree()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(VikuSpacing.md)
                .background(VikuColor.Surface.page)
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            Text(verbatim: title)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
            Text(verbatim: body)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }
}
