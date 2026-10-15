import SwiftUI
import VikuDesignSystem
import VikunjaCore

#if os(iOS)
import UIKit
#endif

/// The appearance picker's per-row preview icon.
extension AppTheme {
    /// `.system` has no single representative color (it tracks whatever the
    /// device's current appearance is), so it gets the half-light/half-dark
    /// glyph instead of a flat swatch — a plain color circle for it looked
    /// arbitrary next to `.light`/`.dark`/`.warm`'s real page-background
    /// colors.
    @ViewBuilder
    var previewIcon: some View {
        switch self {
        case .system:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 16))
                .foregroundStyle(Color.primary, Color.secondary)
                .frame(width: 18, height: 18)
        case .light, .dark, .warm, .nord, .solarized, .forest, .cyberpunk, .terminal, .vaporwave:
            Circle()
                .fill(swatchColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().strokeBorder(.separator, lineWidth: 0.5)
                }
        }
    }

    /// `.light`/`.dark` force their own appearance so the swatch stays
    /// correct regardless of the device's current one. Every other theme
    /// has its own literal palette, so no resolving is needed. Not called
    /// for `.system`.
    private var swatchColor: Color {
        #if os(iOS)
        switch self {
        case .system:
            Color(uiColor: .systemGroupedBackground)
        case .light:
            Color(uiColor: UIColor.systemGroupedBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light),
            ))
        case .dark:
            Color(uiColor: UIColor.systemGroupedBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .dark),
            ))
        case .warm:
            VikuPalette.warm.pageBackground
        case .nord:
            VikuPalette.nord.pageBackground
        case .solarized:
            VikuPalette.solarized.pageBackground
        case .forest:
            VikuPalette.forest.pageBackground
        case .cyberpunk:
            VikuPalette.cyberpunk.pageBackground
        case .terminal:
            VikuPalette.terminal.pageBackground
        case .vaporwave:
            VikuPalette.vaporwave.pageBackground
        }
        #else
        switch self {
        case .warm: VikuPalette.warm.pageBackground
        case .nord: VikuPalette.nord.pageBackground
        case .solarized: VikuPalette.solarized.pageBackground
        case .forest: VikuPalette.forest.pageBackground
        case .cyberpunk: VikuPalette.cyberpunk.pageBackground
        case .terminal: VikuPalette.terminal.pageBackground
        case .vaporwave: VikuPalette.vaporwave.pageBackground
        case .system, .light, .dark: Color.gray.opacity(0.1)
        }
        #endif
    }
}
