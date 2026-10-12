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

        #expect(palette.brand == VikuColor.brandPrimary)
        #expect(palette.pageBackground == Color.platformPageBackground)
        #expect(palette.cardBackground == Color.platformCardBackground)
        #expect(palette.fieldBackground == Color.platformFieldBackground)
        #expect(palette.textSecondary == VikuColor.textSecondary)
        #expect(palette.textTertiary == VikuColor.textTertiary)
        #expect(palette.semanticSuccess == VikuColor.Semantic.success)
        #expect(palette.semanticSuccessText == VikuColor.Semantic.successText)
        #expect(palette.semanticDanger == VikuColor.Semantic.danger)
        #expect(palette.semanticDangerText == VikuColor.Semantic.dangerText)
    }

    @Test
    @available(*, deprecated, message: "Exercises the deprecated VikuColor.Surface aliases on purpose.")
    func `deprecated VikuColor Surface aliases still forward to standard`() {
        #expect(VikuColor.Surface.page == VikuPalette.standard.pageBackground)
        #expect(VikuColor.Surface.card == VikuPalette.standard.cardBackground)
        #expect(VikuColor.Surface.field == VikuPalette.standard.fieldBackground)
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
