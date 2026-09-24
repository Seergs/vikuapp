import SwiftUI

public extension Color {
    /// Builds a `Color` from a `0xRRGGBB` literal, e.g. `Color(hex: 0x196AFF)`.
    internal init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue)
    }

    /// Parses a Vikunja API `hex_color` value (`"RRGGBB"`, with or without a
    /// leading `#`) as it comes back on `Project`/`Label`. Returns `nil` for
    /// the empty string (no color set server-side) or anything malformed,
    /// so callers can fall back to a design-system default.
    init?(vikuHex hexString: String) {
        guard let value = Self.parseVikuHex(hexString) else { return nil }
        self.init(hex: value)
    }

    /// Same parsing as `init?(vikuHex:)`, softened for use as a label accent:
    /// the hue is kept, but saturation/lightness are clamped to the app's
    /// muted-accent band instead of whatever they happened to be picked at.
    /// Vikunja labels carry an arbitrary hex chosen through Vikunja's own web
    /// client (or a previous, more saturated version of this app's own
    /// swatch palette), at any saturation — pinned everywhere a label's color
    /// is drawn as a chip/pill so a task list reads as tinted accents rather
    /// than a row of saturated blocks.
    init?(vikuMutedHex hexString: String) {
        guard let value = Self.parseVikuHex(hexString) else { return nil }
        self = Hue(rgbHex: value).mutedColor()
    }

    private static func parseVikuHex(_ hexString: String) -> UInt32? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 else { return nil }
        return UInt32(hex, radix: 16)
    }
}

/// Just the hue extracted from an RGB hex value, so it can be recombined with
/// a fixed saturation/lightness (`mutedColor()`). Plain math rather than
/// `UIColor`/`NSColor` accessors, since this package also builds for macOS to
/// run its tests, where `UIColor` doesn't exist (see `Color+Platform.swift`).
private struct Hue {
    let degrees: Double

    init(rgbHex hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255

        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent

        guard delta > 0 else {
            self.degrees = 0
            return
        }

        var hue: Double = switch maxComponent {
        case red: ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: (blue - red) / delta + 2
        default: (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 {
            hue += 360
        }
        self.degrees = hue
    }

    /// The app's muted-accent band, in HSL — not `Color(hue:saturation:
    /// brightness:)`'s HSB/HSV, which was tried first and looked wrong:
    /// HSB's "brightness" scales chroma down together with darkness, so at a
    /// muted brightness every hue collapses toward the same gray-brown.
    /// HSL's lightness keeps chroma (and so each hue's identity) at full
    /// strength near the middle of the lightness range, which is exactly
    /// where a muted accent sits.
    func mutedColor(saturation: Double = 0.38, lightness: Double = 0.46) -> Color {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let hPrime = degrees / 60
        let secondLargestComponent = chroma * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let lightnessOffset = lightness - chroma / 2

        let rgb = switch hPrime {
        case 0 ..< 1: RGBFraction(red: chroma, green: secondLargestComponent, blue: 0)
        case 1 ..< 2: RGBFraction(red: secondLargestComponent, green: chroma, blue: 0)
        case 2 ..< 3: RGBFraction(red: 0, green: chroma, blue: secondLargestComponent)
        case 3 ..< 4: RGBFraction(red: 0, green: secondLargestComponent, blue: chroma)
        case 4 ..< 5: RGBFraction(red: secondLargestComponent, green: 0, blue: chroma)
        default: RGBFraction(red: chroma, green: 0, blue: secondLargestComponent)
        }

        return Color(
            .sRGB,
            red: rgb.red + lightnessOffset,
            green: rgb.green + lightnessOffset,
            blue: rgb.blue + lightnessOffset,
        )
    }
}

/// A plain (non-tuple) carrier for the three RGB fractions `mutedColor()`
/// builds up per hue segment, since SwiftLint caps tuples at two members.
private struct RGBFraction {
    let red: Double
    let green: Double
    let blue: Double
}
