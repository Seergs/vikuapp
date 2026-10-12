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

public extension EnvironmentValues {
    @Entry var vikuPalette: VikuPalette = .standard
}
