import Foundation

/// Stable front matter identifiers. Display names live in the String Catalog
/// so one `category` value works in every language.
enum DocumentationCategory: String {
    case basics
    case setup

    var title: String {
        switch self {
        case .basics: String(localized: "Basics")
        case .setup: String(localized: "Setup")
        }
    }
}
