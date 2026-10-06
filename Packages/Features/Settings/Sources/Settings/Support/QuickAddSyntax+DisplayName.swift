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
