import Foundation
import VikunjaCore

/// Product names, so they are not localized. Shown verbatim in the picker.
extension QuickAddSyntax {
    var displayName: String {
        switch self {
        case .todoist: "Todoist"
        case .vikunja: "Vikunja"
        }
    }
}

extension QuickAddMagicMode {
    var displayName: String {
        syntax?.displayName ?? String(localized: "Off", bundle: .module)
    }
}
