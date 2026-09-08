import SwiftUI
import VikunjaCore

/// Color tokens. Values that originate as `oklch(...)` in the design source are
/// pre-converted to sRGB hex once here, rather than converting at runtime.
public enum VikuColor {
    public static let brandPrimary = Color(hex: 0x196AFF)

    public enum Priority {
        public static let urgent = Color(hex: 0xDF202E)
        public static let high = Color(hex: 0xE85E00)
        /// Kept as its own literal (matches `brandPrimary` today) so a future brand
        /// color change doesn't silently change this token too.
        public static let medium = Color(hex: 0x196AFF)
        public static let low = Color(hex: 0x79818D)

        /// The dot color for a task's priority, or `nil` when unset (no dot is
        /// drawn in that case). Single source for the priority-to-color mapping
        /// every compact task row needs.
        public static func dot(for priority: VikunjaTask.Priority) -> Color? {
            switch priority {
            case .unset: nil
            case .low: low
            case .medium: medium
            case .high: high
            case .urgent, .doNow: urgent
            }
        }
    }

    /// Grouped-content backgrounds, one step apart in elevation. Backed by
    /// adaptive iOS system colors so light/dark mode and increased-contrast
    /// settings are handled for free — see `Color+Platform.swift`.
    public enum Surface {
        /// Card background, e.g. a grouped section of rows.
        public static let card = Color.platformCardBackground
        /// Input field / chip background, one step lighter than `card`.
        public static let field = Color.platformFieldBackground
        /// The page canvas behind grouped/carded content.
        public static let page = Color.platformPageBackground
    }

    /// Darker, more legible than the system `.secondary`/`.tertiary` text
    /// styles — matches the design source's own gray scale. Adapts to
    /// light/dark automatically, see `Color+Platform.swift`.
    public static let textSecondary = Color.platformTextSecondary
    public static let textTertiary = Color.platformTextTertiary

    /// Preset swatches offered when picking a color for something the user is
    /// creating (a label, a project, ...). Plain hex strings rather than
    /// `Color`, since `Label.hexColor`/`Project.hexColor` round-trip through
    /// the API as a hex string and this is what a "create ..." UI hands back.
    public enum SwatchPalette {
        public static let swatches: [String] = [
            "8B5CF6", "0EA5E9", "22C55E", "F59E0B", "EF4444", "EC4899",
        ]
    }

    /// Status colors for inline feedback (banners, connection results).
    public enum Semantic {
        public static let success = Color(hex: 0x1FA669)
        /// Kept as its own literal even though it currently matches
        /// `Priority.urgent`, so the two can diverge independently later.
        public static let danger = Color(hex: 0xDF202E)

        /// Darker variants of `success`/`danger`, for text/icons drawn on top
        /// of the low-opacity tinted banner background — `success`/`danger`
        /// themselves are too bright to read comfortably as text.
        public static let successText = Color(hex: 0x15753F)
        public static let dangerText = Color(hex: 0x9E1620)
    }
}
