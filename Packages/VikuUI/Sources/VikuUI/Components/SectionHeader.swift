import SwiftUI
import VikuDesignSystem

public extension View {
    /// The shared look for a list section label ("SUBPROJECTS", "OVERDUE",
    /// "RESULTS"): small, bold, uppercase, lightly kerned, and legible against
    /// `palette.textSecondary` rather than the system header's faint gray.
    func vikuSectionHeader() -> some View {
        modifier(VikuSectionHeaderModifier())
    }
}

/// A plain `View` extension can't declare `@Environment` itself, so the
/// styling lives in this modifier instead.
private struct VikuSectionHeaderModifier: ViewModifier {
    @Environment(\.vikuPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(VikuFont.footnote)
            .fontWeight(.bold)
            .foregroundStyle(palette.textSecondary)
            .textCase(.uppercase)
            .kerning(0.3)
    }
}
