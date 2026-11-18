#if canImport(WidgetKit)
import SwiftUI
import VikuDesignSystem

extension View {
    /// Marks development widgets without taking space from their content or
    /// intercepting task toggles and deep links. Release keeps the original view.
    @ViewBuilder
    func widgetDevBadge(
        alignment: Alignment = .bottomTrailing,
        inset: CGFloat = VikuSpacing.md,
    ) -> some View {
        #if DEBUG
        overlay(alignment: alignment) {
            Text("DEV", bundle: .module)
                .font(VikuFont.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textOnBrand)
                .padding(.horizontal, VikuSpacing.xs)
                .padding(.vertical, VikuSpacing.xxs)
                .background(VikuColor.AccentTint.amber.color, in: Capsule())
                // Stay inside the widget's rounded clipping boundary.
                .padding(inset)
                .accessibilityLabel(Text("Development build", bundle: .module))
                .allowsHitTesting(false)
        }
        #else
        self
        #endif
    }
}
#endif
