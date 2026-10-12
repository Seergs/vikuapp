import SwiftUI
import VikuDesignSystem
import VikunjaCore

extension QuickAddParser.Resolution {
    /// The color a shortcut's text is drawn in inside the title field. `nil`
    /// leaves the text plain, which is what a superseded shortcut gets.
    /// Priority keeps its own literal mapping (`PriorityOption`), which
    /// doesn't depend on the active theme.
    func tint(in palette: VikuPalette) -> Color? {
        switch self {
        case .project:
            palette.brand
        case let .priority(priority):
            PriorityOption.all.first { $0.priority == (priority == .doNow ? .urgent : priority) }?.color
        case let .label(label):
            Color(vikuMutedHex: label.hexColor) ?? palette.brand
        case .newLabel:
            palette.brand
        case .unmatchedProject, .ambiguousProject, .ambiguousLabel:
            palette.semanticDangerText
        case .superseded:
            nil
        }
    }
}
