import Foundation

/// WCAG 2.1 contrast-ratio math (success criterion 1.4.3), used to gate new
/// theme palettes before they ship.
enum ContrastRatio {
    /// Relative luminance of an sRGB color, per the WCAG formula. `red`/
    /// `green`/`blue` are gamma-encoded sRGB components in `0...1` — what
    /// `Color.resolve(in:)` returns for a color built from
    /// `Color(.sRGB, red:green:blue:)` or `Color(hex:)`.
    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// The contrast ratio between two relative luminances, always `>= 1`.
    /// WCAG AA requires `>= 4.5` for normal text, `>= 3` for large text and
    /// non-text UI.
    static func ratio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
