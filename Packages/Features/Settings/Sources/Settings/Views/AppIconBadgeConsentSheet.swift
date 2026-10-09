import SwiftUI
import VikuDesignSystem

/// The soft-ask shown before the OS permission prompt, the first time the
/// user turns on the app-icon-badge toggle. `onAgree` runs
/// `AppIconBadgeViewModel.confirmEnable()`, which is what actually triggers
/// the system authorization request — this sheet only explains what the
/// badge does, so the OS dialog (generic, and shared with push
/// notifications) doesn't land on the user with no context. A small sheet
/// on purpose (`.presentationDetents`), not the full-height scrolling style
/// `NotificationsConsentSheet` uses — there's much less to read here.
struct AppIconBadgeConsentSheet: View {
    let onAgree: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Whether the 4 mock Home Screen icons have animated in — all together,
    /// not staggered, since they're meant to read as one row appearing at
    /// once. See `animateIn()`.
    @State private var areIconsVisible = false
    /// Whether the sample badge number on the mock Viku icon has appeared —
    /// set true slightly after the icon row, so the badge reads as landing
    /// "after" the icon, the way a real badge update would.
    @State private var isBadgeVisible = false

    /// `skeletonIconSize` is ~80% of this — Viku's icon is the point of
    /// this screen, the empty slots are just there to sell the Home Screen
    /// row illusion, not to compete with it.
    private static let vikuIconSize: CGFloat = 68
    private static let skeletonIconSize: CGFloat = 54
    private static let iconSpotCount = 4
    /// Which mock icon is "Viku" — the others are empty placeholders.
    private static let vikuIconIndex = 1
    private static let sampleBadgeCount = 3
    private static let badgeDelay: Duration = .milliseconds(350)

    var body: some View {
        VStack(spacing: VikuSpacing.lg) {
            homeScreenMock

            Divider()

            VStack(spacing: VikuSpacing.sm) {
                Text("Your Tasks, Without Opening the App", bundle: .module)
                    .font(VikuFont.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                // swiftlint:disable:next line_length
                Text("We'll show how many tasks you have due today or overdue right on Viku's icon. For that, iOS will ask for notification permission.", bundle: .module)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task {
            await animateIn()
        }
    }

    /// A row of 4 Home Screen-style icon slots, so the badge reads as "this
    /// is literally what your icon will look like" rather than an abstract
    /// bullet point. Only the second slot is Viku's real icon; the rest are
    /// empty skeletons that exist purely to sell the row — they're smaller
    /// than Viku's so it's the one that pops.
    private var homeScreenMock: some View {
        HStack(alignment: .center, spacing: VikuSpacing.lg) {
            ForEach(0 ..< Self.iconSpotCount, id: \.self) { index in
                iconSpot(index: index)
                    .opacity(areIconsVisible ? 1 : 0)
                    .scaleEffect(areIconsVisible ? 1 : 0.75)
            }
        }
    }

    @ViewBuilder
    private func iconSpot(index: Int) -> some View {
        if index == Self.vikuIconIndex {
            ZStack(alignment: .topTrailing) {
                Image.vikuAppIcon
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.vikuIconSize, height: Self.vikuIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                if isBadgeVisible {
                    Text(verbatim: "\(Self.sampleBadgeCount)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 34, minHeight: 34)
                        .background(VikuColor.Semantic.danger, in: Circle())
                        .offset(x: 12, y: -12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        } else {
            RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous)
                .fill(VikuColor.Surface.field)
                .frame(width: Self.skeletonIconSize, height: Self.skeletonIconSize)
        }
    }

    /// Reveals the whole icon row at once, then pops the sample badge count
    /// in on Viku's — the count arriving visibly "after" the row mirrors
    /// what actually happens once the real badge starts updating.
    private func animateIn() async {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            areIconsVisible = true
        }
        try? await Task.sleep(for: Self.badgeDelay)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            isBadgeVisible = true
        }
    }
}
