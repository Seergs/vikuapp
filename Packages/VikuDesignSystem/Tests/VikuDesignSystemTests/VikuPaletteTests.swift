import SwiftUI
import Testing
@testable import VikuDesignSystem

struct VikuPaletteTests {
    @Test
    func `standard resolves to the same colors as VikuColor`() {
        // Plain `==` rather than `.resolve(in:)`: several of these tokens
        // wrap a platform-dynamic provider (`Color.platformTextSecondary`
        // etc.), and resolving those outside a live rendering environment
        // hangs rather than returning. Each `standard` property is assigned
        // directly from its `VikuColor` counterpart, so structural equality
        // already proves they're the same color.
        let palette = VikuPalette.standard

        #expect(palette.brand == Color(hex: 0x196AFF))
        #expect(palette.pageBackground == Color.platformPageBackground)
        #expect(palette.cardBackground == Color.platformCardBackground)
        #expect(palette.fieldBackground == Color.platformFieldBackground)
        #expect(palette.textSecondary == Color.platformTextSecondary)
        #expect(palette.textTertiary == Color.platformTextTertiary)
        #expect(palette.semanticSuccess == Color(hex: 0x1FA669))
        #expect(palette.semanticSuccessText == Color(hex: 0x15753F))
        #expect(palette.semanticDanger == Color(hex: 0xDF202E))
        #expect(palette.semanticDangerText == Color.platformDangerText)
    }

    @Test
    @available(*, deprecated, message: "Exercises the deprecated VikuColor aliases on purpose.")
    func `deprecated VikuColor aliases still forward to standard`() {
        #expect(VikuColor.Surface.page == VikuPalette.standard.pageBackground)
        #expect(VikuColor.Surface.card == VikuPalette.standard.cardBackground)
        #expect(VikuColor.Surface.field == VikuPalette.standard.fieldBackground)
        #expect(VikuColor.brandPrimary == VikuPalette.standard.brand)
        #expect(VikuColor.Semantic.success == VikuPalette.standard.semanticSuccess)
        #expect(VikuColor.Semantic.successText == VikuPalette.standard.semanticSuccessText)
        #expect(VikuColor.Semantic.danger == VikuPalette.standard.semanticDanger)
        #expect(VikuColor.Semantic.dangerText == VikuPalette.standard.semanticDangerText)
        #expect(VikuColor.textSecondary == VikuPalette.standard.textSecondary)
        #expect(VikuColor.textTertiary == VikuPalette.standard.textTertiary)
    }

    @Test
    func `environment default value is standard`() {
        let environment = EnvironmentValues()

        #expect(environment.vikuPalette == VikuPalette.standard)
    }

    @Test
    func `environment can be overridden`() {
        var environment = EnvironmentValues()
        let custom = VikuPalette(
            brand: .red,
            pageBackground: .black,
            cardBackground: .black,
            fieldBackground: .black,
            textSecondary: .white,
            textTertiary: .white,
            semanticSuccess: .green,
            semanticSuccessText: .green,
            semanticDanger: .red,
            semanticDangerText: .red,
        )

        environment.vikuPalette = custom

        #expect(environment.vikuPalette == custom)
    }
}
