import SwiftUI
import VikuDesignSystem

public extension View {
    /// The shared look for a list section label ("SUBPROJECTS", "OVERDUE",
    /// "RESULTS"): small, bold, uppercase, lightly kerned, and legible against
    /// `VikuColor.textSecondary` rather than the system header's faint gray.
    func vikuSectionHeader() -> some View {
        font(VikuFont.footnote)
            .fontWeight(.bold)
            .foregroundStyle(VikuColor.textSecondary)
            .textCase(.uppercase)
            .kerning(0.3)
    }
}
