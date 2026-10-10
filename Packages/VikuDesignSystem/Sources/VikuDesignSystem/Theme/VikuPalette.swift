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
    static let standard = VikuPalette(
        brand: VikuColor.brandPrimary,
        pageBackground: VikuColor.Surface.page,
        cardBackground: VikuColor.Surface.card,
        fieldBackground: VikuColor.Surface.field,
        textSecondary: VikuColor.textSecondary,
        textTertiary: VikuColor.textTertiary,
        semanticSuccess: VikuColor.Semantic.success,
        semanticSuccessText: VikuColor.Semantic.successText,
        semanticDanger: VikuColor.Semantic.danger,
        semanticDangerText: VikuColor.Semantic.dangerText,
    )
}

public extension EnvironmentValues {
    @Entry var vikuPalette: VikuPalette = .standard
}
