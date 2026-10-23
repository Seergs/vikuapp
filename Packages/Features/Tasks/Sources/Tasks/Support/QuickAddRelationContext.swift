import VikunjaCore
import VikuUI

/// Carries which task/relation kind an inline-created task (from the "add
/// relation"/"add subtask" picker, see `TaskDetailViewModel.makeQuickAddTaskViewModel`)
/// is being created for, so `QuickAddSheetView` can show a banner for it.
public struct QuickAddRelationContext: Sendable {
    public let kind: RelationKind
    public let parentTaskTitle: String

    public init(kind: RelationKind, parentTaskTitle: String) {
        self.kind = kind
        self.parentTaskTitle = parentTaskTitle
    }

    /// "Subtask of: <title>" for `.subtask`; "<kind name>: <title>" for
    /// every other kind (reusing `RelationKind.localizedDisplayName` rather
    /// than a bespoke sentence per kind, to avoid nine near-duplicate
    /// catalog entries).
    public var bannerText: String {
        switch kind {
        case .subtask:
            String(localized: "Subtask of: \(parentTaskTitle)", bundle: .module)
        default:
            String(localized: "\(kind.localizedDisplayName): \(parentTaskTitle)", bundle: .module)
        }
    }
}
