import SwiftUI

public extension VikuPalette {
    /// Neutral system surfaces and text for utility sheets, retaining the theme's
    /// accent pair. This is idempotent so nested pickers keep the same appearance.
    /// These surface tokens style content; the sheet's presentation material stays
    /// under the system's control and must not be covered with a page background.
    var nativeSheet: VikuPalette {
        var palette = Self.nativeSheetBase
        palette.brand = brand
        palette.brandForeground = brandForeground
        return palette
    }

    /// Reuse the dynamic color providers across updates and nested presentations.
    /// Recreating custom providers would give equal-looking colors new identities.
    private static let nativeSheetBase = VikuPalette(
        brand: standard.brand,
        pageBackground: .platformPageBackground,
        cardBackground: .platformCardBackground,
        fieldBackground: .platformFieldBackground,
        textSecondary: .platformNativeTextSecondary,
        textTertiary: .platformNativeTextTertiary,
        semanticSuccess: .green,
        semanticSuccessText: .platformDateHighlightText,
        semanticDanger: .red,
        semanticDangerText: .platformDangerText,
        dateHighlightText: .platformDateHighlightText,
    )
}

public extension View {
    /// Apply to the entire content returned by `.sheet`, outside the sheet view
    /// itself, so its root's environment reads and all descendants use native
    /// surfaces and text. Keeps the inherited color scheme and theme accent.
    /// Does not replace the system presentation background or add glass effects.
    func vikuNativeSheetAppearance() -> some View {
        modifier(NativeSheetAppearanceModifier())
    }
}

private struct NativeSheetAppearanceModifier: ViewModifier {
    @Environment(\.vikuPalette) private var palette

    func body(content: Content) -> some View {
        content
            .environment(\.vikuPalette, palette.nativeSheet)
            .tint(palette.brand)
    }
}
