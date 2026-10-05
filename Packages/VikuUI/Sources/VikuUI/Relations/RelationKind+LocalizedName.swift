import Foundation
import VikunjaCore

public extension RelationKind {
    /// Localized section title for this relation kind. Lives in `VikuUI` rather
    /// than `VikunjaCore` so the strings resolve against this module's String
    /// Catalog, and every screen that lists or picks relations shares one mapping.
    var localizedDisplayName: String {
        switch self {
        case .subtask: String(localized: "Subtasks", bundle: .module)
        case .parenttask: String(localized: "Parent Task", bundle: .module)
        case .related: String(localized: "Related Tasks", bundle: .module)
        case .duplicateof: String(localized: "Duplicate Of", bundle: .module)
        case .duplicates: String(localized: "Duplicates", bundle: .module)
        case .blocking: String(localized: "Blocks", bundle: .module)
        case .blocked: String(localized: "Depends On", bundle: .module)
        case .precedes: String(localized: "Precedes", bundle: .module)
        case .follows: String(localized: "Follows", bundle: .module)
        case .copiedfrom: String(localized: "Copied From", bundle: .module)
        case .copiedto: String(localized: "Copied To", bundle: .module)
        }
    }
}
