import SwiftUI
import VikuDesignSystem

/// Floating action button for quick task creation, matching the design
/// mockup's FAB: an opaque, brand-colored circle with a layered shadow,
/// carrying its own elevation rather than relying on any system chrome.
/// `.tabViewBottomAccessory` was tried first, but iOS always paints a glass
/// background behind its content and centers it over the tab bar — there's
/// no way to make that background disappear or anchor it to a corner — so
/// this is placed via a plain `.overlay(alignment: .bottomTrailing)` on
/// `MainTabView` instead. `onTap` is supplied by `MainTabView` to present
/// `Tasks`' `QuickAddSheetView`.
struct QuickAddButton: View {
    private let diameter: CGFloat = 56

    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(VikuColor.brandPrimary, in: Circle())
                .shadow(color: VikuColor.brandPrimary.opacity(0.4), radius: 10, x: 0, y: 6)
                .shadow(color: VikuColor.brandPrimary.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Quick Add"))
    }
}
