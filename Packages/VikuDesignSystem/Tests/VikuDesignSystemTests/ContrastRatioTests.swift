import SwiftUI
import Testing
@testable import VikuDesignSystem

struct ContrastRatioTests {
    @Test
    func `identical luminances have a ratio of exactly one`() {
        let luminance = ContrastRatio.luminance(red: 0.4, green: 0.4, blue: 0.4)
        #expect(ContrastRatio.ratio(luminance, luminance) == 1)
    }

    @Test
    func `pure black against pure white has the maximum ratio of twenty one`() {
        let black = ContrastRatio.luminance(red: 0, green: 0, blue: 0)
        let white = ContrastRatio.luminance(red: 1, green: 1, blue: 1)
        #expect(abs(ContrastRatio.ratio(black, white) - 21) < 0.01)
    }

    @Test
    func `ratio is symmetric regardless of argument order`() {
        let first = ContrastRatio.luminance(red: 0.8, green: 0.2, blue: 0.5)
        let second = ContrastRatio.luminance(red: 0.1, green: 0.6, blue: 0.3)
        #expect(ContrastRatio.ratio(first, second) == ContrastRatio.ratio(second, first))
    }
}

/// WCAG AA thresholds this suite gates palettes against: 4.5:1 for normal
/// text, 3:1 for large text and non-text UI.
private enum WCAGThreshold {
    static let normalText = 4.5
    /// `textTertiary` is this app's de-emphasized tier (captions, counts,
    /// disabled-looking chrome) — the same role Apple's own `.tertiaryLabel`
    /// plays, which Apple's HIG explicitly doesn't hold to body-text
    /// contrast. Graded against the "large text / non-text UI" floor instead.
    static let tertiaryText = 3.0
}

/// Reference (non-rendering) RGB for Apple's system grouped-content
/// materials, in gamma-encoded sRGB. These back `standard`'s `pageBackground`/
/// `cardBackground` (`.systemGroupedBackground` / `.secondarySystemGroupedBackground`
/// via `Color+Platform.swift`) and are well-documented, stable values — used
/// only here, to WCAG-check `standard` with real numbers, since resolving the
/// actual adaptive `Color` hangs outside a live rendering host (no App/Scene),
/// which is what `swift test` runs in.
///
/// `fieldBackground` (`.tertiarySystemFill`) is intentionally not covered:
/// it's a translucent fill with no single pinned RGB in this codebase, so
/// there's no literal to check against. That surface still relies on a
/// manual pass in light, dark and Increase Contrast.
private enum StandardSurfaceReferenceRGB {
    enum Page {
        static let light = ReferenceRGB(red: 0.949, green: 0.949, blue: 0.969) // #F2F2F7
        static let dark = ReferenceRGB(red: 0.0, green: 0.0, blue: 0.0) // #000000
    }

    enum Card {
        static let light = ReferenceRGB(red: 1.0, green: 1.0, blue: 1.0) // #FFFFFF
        static let dark = ReferenceRGB(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
    }
}

private func assertMeetsWCAG(_ label: String, text: ReferenceRGB, background: ReferenceRGB, minimumRatio: Double) {
    let textLuminance = ContrastRatio.luminance(red: text.red, green: text.green, blue: text.blue)
    let backgroundLuminance = ContrastRatio.luminance(
        red: background.red,
        green: background.green,
        blue: background.blue,
    )
    let ratio = ContrastRatio.ratio(textLuminance, backgroundLuminance)

    #expect(ratio >= minimumRatio, "\(label): contrast ratio \(ratio) is below the required \(minimumRatio):1")
}

struct StandardPaletteContrastTests {
    @Test
    func `textSecondary meets normal text contrast on page and card, light and dark`() {
        assertMeetsWCAG(
            "textSecondary on page, light",
            text: Color.TextSecondaryRGB.light,
            background: StandardSurfaceReferenceRGB.Page.light,
            minimumRatio: WCAGThreshold.normalText,
        )
        assertMeetsWCAG(
            "textSecondary on page, dark",
            text: Color.TextSecondaryRGB.dark,
            background: StandardSurfaceReferenceRGB.Page.dark,
            minimumRatio: WCAGThreshold.normalText,
        )
        assertMeetsWCAG(
            "textSecondary on card, light",
            text: Color.TextSecondaryRGB.light,
            background: StandardSurfaceReferenceRGB.Card.light,
            minimumRatio: WCAGThreshold.normalText,
        )
        assertMeetsWCAG(
            "textSecondary on card, dark",
            text: Color.TextSecondaryRGB.dark,
            background: StandardSurfaceReferenceRGB.Card.dark,
            minimumRatio: WCAGThreshold.normalText,
        )
    }

    @Test
    func `textTertiary meets the large text and non-text UI floor on page and card, light and dark`() {
        assertMeetsWCAG(
            "textTertiary on page, light",
            text: Color.TextTertiaryRGB.light,
            background: StandardSurfaceReferenceRGB.Page.light,
            minimumRatio: WCAGThreshold.tertiaryText,
        )
        assertMeetsWCAG(
            "textTertiary on page, dark",
            text: Color.TextTertiaryRGB.dark,
            background: StandardSurfaceReferenceRGB.Page.dark,
            minimumRatio: WCAGThreshold.tertiaryText,
        )
        assertMeetsWCAG(
            "textTertiary on card, light",
            text: Color.TextTertiaryRGB.light,
            background: StandardSurfaceReferenceRGB.Card.light,
            minimumRatio: WCAGThreshold.tertiaryText,
        )
        assertMeetsWCAG(
            "textTertiary on card, dark",
            text: Color.TextTertiaryRGB.dark,
            background: StandardSurfaceReferenceRGB.Card.dark,
            minimumRatio: WCAGThreshold.tertiaryText,
        )
    }
}
