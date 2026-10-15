import SwiftUI

/// A theme's full set of colors. `standard` reproduces `VikuColor`'s current
/// values exactly, including its adaptive light/dark providers, so introducing
/// this type is zero visual change. Call sites keep reading `VikuColor`
/// directly until a later migration phase moves them onto
/// `@Environment(\.vikuPalette)`.
///
/// `Priority.*`'s mapping and `SwatchPalette` stay outside the palette: they
/// don't depend on the active theme.
public struct VikuPalette: Sendable, Equatable {
    public var brand: Color
    /// The color to draw text/icons in when they sit directly on top of a
    /// `brand`-filled surface (the quick-add FAB's "+", a selected filter
    /// chip's label, a primary CTA's label). Defaults to `.white` for every
    /// palette whose `brand` is dark/saturated enough for that to read, but
    /// a handful of palettes (`terminal`, `vaporwave`) have a very light
    /// `brand` where white text nearly disappears — those override this to
    /// `.black` instead. Never derived at call sites from `brand`'s
    /// luminance, so each palette can be eyeballed and tuned independently.
    public var brandForeground: Color
    public var pageBackground: Color
    public var cardBackground: Color
    public var fieldBackground: Color
    public var textSecondary: Color
    public var textTertiary: Color
    public var semanticSuccess: Color
    public var semanticSuccessText: Color
    public var semanticDanger: Color
    public var semanticDangerText: Color

    public init(
        brand: Color,
        brandForeground: Color = .white,
        pageBackground: Color,
        cardBackground: Color,
        fieldBackground: Color,
        textSecondary: Color,
        textTertiary: Color,
        semanticSuccess: Color,
        semanticSuccessText: Color,
        semanticDanger: Color,
        semanticDangerText: Color,
    ) {
        self.brand = brand
        self.brandForeground = brandForeground
        self.pageBackground = pageBackground
        self.cardBackground = cardBackground
        self.fieldBackground = fieldBackground
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.semanticSuccess = semanticSuccess
        self.semanticSuccessText = semanticSuccessText
        self.semanticDanger = semanticDanger
        self.semanticDangerText = semanticDangerText
    }
}

public extension VikuPalette {
    /// `brand`/`pageBackground`/`cardBackground`/`fieldBackground`/
    /// `semanticSuccess`/`semanticDanger`/etc. read their underlying color
    /// providers directly, not `VikuColor`, which now forwards here instead
    /// (forwarding the other way would recurse).
    static let standard = VikuPalette(
        brand: Color(hex: 0x196AFF),
        pageBackground: Color.platformPageBackground,
        cardBackground: Color.platformCardBackground,
        fieldBackground: Color.platformFieldBackground,
        textSecondary: Color.platformTextSecondary,
        textTertiary: Color.platformTextTertiary,
        semanticSuccess: Color(hex: 0x1FA669),
        semanticSuccessText: Color(hex: 0x15753F),
        semanticDanger: Color(hex: 0xDF202E),
        semanticDangerText: Color.platformDangerText,
    )
}

public extension VikuPalette {
    /// A light-scheme palette with warm off-white surfaces instead of
    /// `standard`'s cool system grays, same brand accent. Entirely literal
    /// (no platform-adaptive providers) since it never follows the system
    /// appearance — `ThemeCenter.colorScheme` pins `.warm` to `.light`.
    /// `textSecondary` reuses `standard`'s light-mode value; `textTertiary`
    /// is a touch darker than `standard`'s own, since the warmer (less
    /// bright) surfaces below would otherwise fail the WCAG floor
    /// `WarmPaletteContrastTests` checks it against.
    static let warm = VikuPalette(
        brand: Color(hex: 0x196AFF),
        pageBackground: Color(hex: 0xFBF7F0),
        cardBackground: Color(hex: 0xFFFDF8),
        fieldBackground: Color(hex: 0xF8F1E6),
        textSecondary: Color(
            .sRGB,
            red: Color.TextSecondaryRGB.light.red,
            green: Color.TextSecondaryRGB.light.green,
            blue: Color.TextSecondaryRGB.light.blue,
        ),
        textTertiary: Color(hex: 0x7A7D85),
        semanticSuccess: Color(hex: 0x1FA669),
        semanticSuccessText: Color(hex: 0x15753F),
        semanticDanger: Color(hex: 0xDF202E),
        semanticDangerText: Color(hex: 0x9E1721),
    )
}

public extension VikuPalette {
    /// Arctic, blue-gray dark palette modeled on the Nord color scheme
    /// (nordtheme.com). Entirely literal, same reasoning as `warm`:
    /// `ThemeCenter.colorScheme` pins `.nord` to `.dark`. `textTertiary` uses
    /// Nord's frost blue (nord9) rather than its own comment gray (nord3),
    /// which falls well short of the WCAG floor against these surfaces;
    /// `semanticDangerText` is a brightened aurora red for the same reason
    /// (nord11 itself is too dark against `card`). Contrast verified by
    /// `NordPaletteContrastTests`.
    static let nord = VikuPalette(
        brand: Color(hex: 0x88C0D0),
        pageBackground: Color(hex: 0x2E3440),
        cardBackground: Color(hex: 0x3B4252),
        fieldBackground: Color(hex: 0x434C5E),
        textSecondary: Color(hex: 0xD8DEE9),
        textTertiary: Color(hex: 0x81A1C1),
        semanticSuccess: Color(hex: 0xA3BE8C),
        semanticSuccessText: Color(hex: 0xA3BE8C),
        semanticDanger: Color(hex: 0xBF616A),
        semanticDangerText: Color(hex: 0xE8A1A6),
    )

    /// Desaturated base16 dark palette modeled on Solarized Dark (Ethan
    /// Schoonover). `card`/`field` share one value since Solarized's own
    /// dark mode only defines two background tones (base03/base02);
    /// `textTertiary` is a custom cyan-gray between Solarized's base01 and
    /// base00, since both official tones fall short of the WCAG floor here.
    /// `semanticSuccessText`/`semanticDangerText` brighten Solarized's
    /// green/red for text-on-card contrast. Pinned to `.dark`. Contrast
    /// verified by `SolarizedPaletteContrastTests`.
    static let solarized = VikuPalette(
        brand: Color(hex: 0x268BD2),
        pageBackground: Color(hex: 0x002B36),
        cardBackground: Color(hex: 0x073642),
        fieldBackground: Color(hex: 0x073642),
        textSecondary: Color(hex: 0x93A1A1),
        textTertiary: Color(hex: 0x6C8083),
        semanticSuccess: Color(hex: 0x859900),
        semanticSuccessText: Color(hex: 0x93A621),
        semanticDanger: Color(hex: 0xDC322F),
        semanticDangerText: Color(hex: 0xEA7A73),
    )

    /// A light-scheme palette with sage/moss surfaces and a forest-green
    /// accent: `warm`'s cozy sibling, pulled toward green rather than peach.
    /// Entirely literal, pinned to `.light`. Contrast verified by
    /// `ForestPaletteContrastTests`.
    static let forest = VikuPalette(
        brand: Color(hex: 0x3F7D54),
        pageBackground: Color(hex: 0xF0EFE2),
        cardBackground: Color(hex: 0xFAF9EF),
        fieldBackground: Color(hex: 0xE7E4CE),
        textSecondary: Color(hex: 0x4A4438),
        textTertiary: Color(hex: 0x847C68),
        semanticSuccess: Color(hex: 0x3F7D54),
        semanticSuccessText: Color(hex: 0x2C5B3C),
        semanticDanger: Color(hex: 0xB3503C),
        semanticDangerText: Color(hex: 0x8C3824),
    )

    /// Neon magenta-and-cyan dark palette on a near-black purple canvas.
    /// Pinned to `.dark`. Contrast verified by `CyberpunkPaletteContrastTests`.
    static let cyberpunk = VikuPalette(
        brand: Color(hex: 0xFF2E97),
        pageBackground: Color(hex: 0x0B0714),
        cardBackground: Color(hex: 0x181025),
        fieldBackground: Color(hex: 0x241A38),
        textSecondary: Color(hex: 0xD9D6F0),
        textTertiary: Color(hex: 0x79698F),
        semanticSuccess: Color(hex: 0x39FF14),
        semanticSuccessText: Color(hex: 0x39FF14),
        semanticDanger: Color(hex: 0xFF2A4D),
        semanticDangerText: Color(hex: 0xFF6B86),
    )

    /// Phosphor-green-on-black dark palette evoking a CRT terminal. Pinned
    /// to `.dark`. `brandForeground` is `.black`: `brand` itself is a very
    /// light neon green, where white text/icons (the quick-add "+", a
    /// selected filter chip's label) nearly vanish. Contrast verified by
    /// `TerminalPaletteContrastTests`.
    static let terminal = VikuPalette(
        brand: Color(hex: 0x33FF66),
        brandForeground: .black,
        pageBackground: Color(hex: 0x000000),
        cardBackground: Color(hex: 0x071007),
        fieldBackground: Color(hex: 0x0F1C0F),
        textSecondary: Color(hex: 0xB6FFC2),
        textTertiary: Color(hex: 0x3A7A46),
        semanticSuccess: Color(hex: 0x33FF66),
        semanticSuccessText: Color(hex: 0x33FF66),
        semanticDanger: Color(hex: 0xFF4433),
        semanticDangerText: Color(hex: 0xFF8066),
    )

    /// Neon pink-and-cyan dark palette on a deep indigo canvas, evoking 80s
    /// synthwave. Pinned to `.dark`. `brandForeground` is `.black`, same
    /// reasoning as `terminal`: `brand` is a very light neon cyan. Contrast
    /// verified by `VaporwavePaletteContrastTests`.
    static let vaporwave = VikuPalette(
        brand: Color(hex: 0x4DEBFF),
        brandForeground: .black,
        pageBackground: Color(hex: 0x190A2E),
        cardBackground: Color(hex: 0x241347),
        fieldBackground: Color(hex: 0x30185C),
        textSecondary: Color(hex: 0xEBD9FF),
        textTertiary: Color(hex: 0x836B9E),
        semanticSuccess: Color(hex: 0x3DFFC0),
        semanticSuccessText: Color(hex: 0x3DFFC0),
        semanticDanger: Color(hex: 0xFF3864),
        semanticDangerText: Color(hex: 0xFF7A96),
    )
}

public extension EnvironmentValues {
    @Entry var vikuPalette: VikuPalette = .standard
}
