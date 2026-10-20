import SwiftUI
import VikunjaCore

/// Color tokens. Values that originate as `oklch(...)` in the design source are
/// pre-converted to sRGB hex once here, rather than converting at runtime.
///
/// Most of these used to be the app's only color tokens, forwarding to
/// `VikuPalette.standard` as deprecated aliases while every call site
/// migrated to `@Environment(\.vikuPalette)`. That migration is done for the
/// app target and every feature module. What's left here is intentionally
/// static:
///
/// - `brandPrimary`, `Surface.page`, `textSecondary`, `textTertiary` and
///   `Semantic.dangerText`: read by `VikuWidgetKit`, which runs in a separate
///   process and has no access to the app's `Environment`. They stay pinned
///   to `.standard` until widgets read the active theme from the shared App
///   Group (deferred, see `docs/THEMING.md` phase F5).
/// - `Priority.*` and `SwatchPalette.*`: never depended on the theme in the
///   first place.
public enum VikuColor {
    /// Kept for `VikuWidgetKit`, see the type's doc comment.
    public static let brandPrimary = VikuPalette.standard.brand

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

    /// The page canvas behind grouped/carded content. Kept for
    /// `VikuWidgetKit`, see this type's doc comment.
    public enum Surface {
        public static let page = VikuPalette.standard.pageBackground
    }

    /// Darker, more legible than the system `.secondary`/`.tertiary` text
    /// styles, matches the design source's own gray scale. Adapts to
    /// light/dark automatically, see `Color+Platform.swift`. Kept for
    /// `VikuWidgetKit`, see this type's doc comment.
    public static let textSecondary = VikuPalette.standard.textSecondary
    public static let textTertiary = VikuPalette.standard.textTertiary

    /// Marks a pseudo-project's *kind* (Favorites, a saved filter) rather than
    /// anything the user picked, so — like `VikuSavedFilterBadge`'s own
    /// tint — these stay fixed regardless of the active `vikuPalette`.
    public enum ProjectBadge {
        public static let favorite = Color(hex: 0xC2872F)
        public static let filter = Color(hex: 0x0A5FD6)

        /// `.project` has no badge color of its own — a real project draws
        /// its hex-color swatch instead — so this returns `.clear` for it
        /// rather than being called at all.
        public static func tint(for kind: ProjectKind) -> Color {
            switch kind {
            case .favorites: favorite
            case .savedFilter: filter
            case .project: .clear
            }
        }
    }

    /// Preset swatches offered when picking a color for something the user is
    /// creating (a project, ...). Plain hex strings rather than `Color`,
    /// since `Label.hexColor`/`Project.hexColor` round-trip through the API
    /// as a hex string and this is what a "create ..." UI hands back.
    public enum SwatchPalette {
        public static let swatches: [String] = [
            "8B5CF6", "0EA5E9", "22C55E", "F59E0B", "EF4444", "EC4899",
        ]

        /// Preset swatches for creating a *label*: the same hues as
        /// `swatches`, pre-muted to `Color.vikuMutedHex`'s saturation/
        /// lightness (38%/46% HSL). A label chip re-mutes its color at
        /// display time regardless of what's stored, so this doesn't change
        /// how this app renders a label created from these swatches — it
        /// keeps the *stored* hex already elegant for any other Vikunja
        /// client (web, Android, ...) that draws a label's color at full
        /// saturation. Kept separate from `swatches` since project colors
        /// aren't muted.
        public static let labelSwatches: [String] = [
            "6449A2", "4986A2", "49A26A", "A28149", "A24949", "A24975",
        ]
    }

    /// Status color for inline feedback. Kept for `VikuWidgetKit`'s "Overdue"
    /// label, see this type's doc comment. Adapts to a brighter red in dark
    /// mode (see `Color+Platform.swift`) so it stays legible there.
    public enum Semantic {
        public static let dangerText = VikuPalette.standard.semanticDangerText
    }
}
