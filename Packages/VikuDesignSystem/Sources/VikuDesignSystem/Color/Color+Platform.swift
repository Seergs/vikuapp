import SwiftUI

/// Platform-adaptive backgrounds backing `VikuColor.Surface`. Wrapped here so
/// the token file itself stays free of `#if os(...)` branching — this package
/// also builds for macOS to run its tests, where `UIColor` doesn't exist.
extension Color {
    static var platformCardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.1)
        #endif
    }

    static var platformFieldBackground: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color.gray.opacity(0.15)
        #endif
    }

    /// The page canvas behind grouped content — what `.insetGrouped` lists
    /// use automatically, needed explicitly by a `.plain` list (paired with
    /// `.scrollContentBackground(.hidden)`) that hand-draws its own cards.
    static var platformPageBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.05)
        #endif
    }

    /// The light/dark RGB pair backing `platformTextSecondary`'s iOS
    /// `UIColor` provider below, named so `ContrastRatioTests` can WCAG-check
    /// them directly instead of resolving the adaptive `Color` itself, which
    /// hangs outside a live rendering host (see that test file's doc comment).
    enum TextSecondaryRGB {
        static let light = ReferenceRGB(red: 0.29, green: 0.30, blue: 0.33)
        static let dark = ReferenceRGB(red: 0.72, green: 0.73, blue: 0.75)
    }

    enum TextTertiaryRGB {
        static let light = ReferenceRGB(red: 0.54, green: 0.55, blue: 0.58)
        static let dark = ReferenceRGB(red: 0.49, green: 0.50, blue: 0.52)
    }

    /// A darker, more legible secondary text color than `UIColor.secondaryLabel`
    /// — matches the design source's own gray scale rather than the system default.
    static var platformTextSecondary: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? TextSecondaryRGB.dark : TextSecondaryRGB.light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #elseif os(macOS)
        Color(nsColor: .secondaryLabelColor)
        #else
        Color.secondary
        #endif
    }

    static var platformTextTertiary: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? TextTertiaryRGB.dark : TextTertiaryRGB.light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #elseif os(macOS)
        Color(nsColor: .tertiaryLabelColor)
        #else
        Color.secondary
        #endif
    }

    /// Resolves to the same adaptive black/white as `Color.primary`, but as a
    /// concrete `Color` rather than SwiftUI's `.primary` `HierarchicalShapeStyle`.
    /// Use this (not `Color.primary`) for text that sits inside a `ToolbarItem`:
    /// iOS 26 wraps toolbar content in its own Liquid Glass background, and
    /// hierarchical styles (`.primary`/`.secondary`/`.tertiary`) get an
    /// automatic vibrancy blend with that glass, which on real device
    /// compositing (the Simulator renders Liquid Glass flatter and doesn't
    /// show this) washes the text out against saturated custom-theme card
    /// colors (Solarized, Cyberpunk, Terminal, Vaporwave). A concrete color
    /// like this one isn't a `HierarchicalShapeStyle`, so it renders flat
    /// instead of vibrancy-blended.
    public static var platformTextPrimary: Color {
        #if os(iOS)
        Color(uiColor: .label)
        #elseif os(macOS)
        Color(nsColor: .labelColor)
        #else
        Color.primary
        #endif
    }

    /// The light-mode `dangerText` hex reads as near-black on a dark
    /// background (e.g. widgets in dark mode), so dark mode swaps in the same
    /// brighter red iOS itself uses for `.systemRed` in dark mode.
    static var platformDangerText: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
                : UIColor(red: 0.62, green: 0.09, blue: 0.13, alpha: 1)
        })
        #elseif os(macOS)
        Color(nsColor: .systemRed)
        #else
        Color.red
        #endif
    }
}

/// A plain (non-tuple) RGB carrier for the reference values above, since
/// SwiftLint caps tuples at two members — mirrors `Color+Hex.swift`'s own
/// `RGBFraction` for the same reason.
struct ReferenceRGB {
    let red: Double
    let green: Double
    let blue: Double
}
