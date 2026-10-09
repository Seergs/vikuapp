import SwiftUI
import VikuDesignSystem

/// The soft-ask shown before the OS permission prompt, the first time the
/// user turns on the app-icon-badge toggle. `onAgree` runs
/// `AppIconBadgeViewModel.confirmEnable()`, which is what actually triggers
/// the system authorization request — this sheet only explains what the
/// badge does, so the OS dialog (generic, and shared with push
/// notifications) doesn't land on the user with no context.
struct AppIconBadgeConsentSheet: View {
    let onAgree: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.lg) {
            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
                        .fill(VikuColor.brandPrimary)
                        .frame(width: 52, height: 52)
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("Show Task Count on Icon", bundle: .module)
                    .font(VikuFont.title2)
                    .fontWeight(.bold)

                Text(
                    """
                    Viku can show a number on its Home Screen icon for tasks that are \
                    overdue or due today, so you can check at a glance.
                    """,
                    bundle: .module,
                )
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
            }

            Text(
                """
                This uses the same iOS permission as notifications, but Viku won't send you \
                any alerts or sounds unless you turn that on separately.
                """,
                bundle: .module,
            )
            .font(VikuFont.footnote)
            .foregroundStyle(VikuColor.textTertiary)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))

            VStack(spacing: VikuSpacing.sm + VikuSpacing.xs) {
                Button {
                    onAgree()
                    dismiss()
                } label: {
                    Text("Enable", bundle: .module)
                        .font(VikuFont.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                }
                .buttonStyle(.borderedProminent)

                Button(String(localized: "Not Now", bundle: .module)) { dismiss() }
                    .font(VikuFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(VikuColor.textSecondary)
            }
        }
        .padding(.horizontal, VikuSpacing.md)
        .padding(.top, VikuSpacing.xl)
        .padding(.bottom, VikuSpacing.md)
        .presentationDragIndicator(.visible)
    }
}
