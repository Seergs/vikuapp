import SwiftUI
import Testing
@testable import VikuDesignSystem

struct DateHighlightContrastTests {
    @Test(arguments: [
        VikuPalette.warm, .nord, .solarized, .forest, .cyberpunk, .terminal, .vaporwave,
    ])
    func `date text meets normal text contrast on custom fields`(_ palette: VikuPalette) {
        let environment = EnvironmentValues()
        let foreground = palette.dateHighlightText.resolve(in: environment)
        let background = palette.fieldBackground.resolve(in: environment)
        let foregroundLuminance = ContrastRatio.luminance(
            red: Double(foreground.red), green: Double(foreground.green), blue: Double(foreground.blue),
        )
        let backgroundLuminance = ContrastRatio.luminance(
            red: Double(background.red), green: Double(background.green), blue: Double(background.blue),
        )
        #expect(ContrastRatio.ratio(foregroundLuminance, backgroundLuminance) >= 4.5)
    }

    @Test func `adaptive date text meets contrast on reference field surfaces`() {
        // Standard fields are translucent UIKit materials. These conservative reference
        // surfaces exercise the RGB actually used by the token; actual materials still
        // require a manual light/dark and Increase Contrast pass in a rendering host.
        let lightSurface = ReferenceRGB(red: 0.875, green: 0.875, blue: 0.886)
        let darkSurface = ReferenceRGB(red: 0.263, green: 0.263, blue: 0.263)
        for (foreground, background) in [(DateHighlightRGB.light, lightSurface), (DateHighlightRGB.dark, darkSurface)] {
            let text = ContrastRatio.luminance(red: foreground.red, green: foreground.green, blue: foreground.blue)
            let field = ContrastRatio.luminance(red: background.red, green: background.green, blue: background.blue)
            #expect(ContrastRatio.ratio(text, field) >= 4.5)
        }
    }
}
