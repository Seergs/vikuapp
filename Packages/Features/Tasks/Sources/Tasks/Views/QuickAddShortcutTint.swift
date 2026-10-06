import SwiftUI
import VikuDesignSystem
import VikunjaCore

extension QuickAddParser.Resolution {
    /// The color a shortcut's text is drawn in inside the title field. `nil`
    /// leaves the text plain, which is what a superseded shortcut gets.
    var tint: Color? {
        switch self {
        case .project:
            VikuColor.brandPrimary
        case let .priority(priority):
            PriorityOption.all.first { $0.priority == (priority == .doNow ? .urgent : priority) }?.color
        case let .label(label):
            Color(vikuMutedHex: label.hexColor) ?? VikuColor.brandPrimary
        case .newLabel:
            VikuColor.brandPrimary
        case .unmatchedProject, .ambiguousProject, .ambiguousLabel:
            VikuColor.Semantic.dangerText
        case .superseded:
            nil
        }
    }
}
