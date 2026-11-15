import Foundation

public extension VikunjaError {
    var isBucketCapacityError: Bool {
        switch self {
        case .bucketFull, .bucketCapacity: true
        default: false
        }
    }

    /// Completion can originate outside Kanban, so identify the destination
    /// and explain the rejected action instead of referring to “this column”.
    func completionFailureMessage(isDone: Bool, isBulk: Bool = false) -> String {
        if case let .bucketCapacity(column, project) = self {
            if isBulk {
                return String(
                    localized: """
                    No tasks were changed. Column “\(column)” in the “\(project)” Kanban board cannot fit the selection.
                    """,
                    bundle: .module,
                )
            }
            return isDone
                ? String(
                    localized: """
                    Couldn’t complete. Column “\(column)” in the “\(project)” Kanban board is full.
                    """,
                    bundle: .module,
                )
                : String(
                    localized: """
                    Couldn’t mark as pending. Column “\(column)” in the “\(project)” Kanban board is full.
                    """,
                    bundle: .module,
                )
        }
        guard self == .bucketFull else { return displayMessage }
        if isBulk {
            return String(
                localized: "No tasks were changed. A destination column in the Kanban board cannot fit the selection.",
                bundle: .module,
            )
        }
        return isDone
            ? String(
                localized: "Couldn’t complete. A destination column in this task’s Kanban board is full.",
                bundle: .module,
            )
            : String(
                localized: "Couldn’t mark as pending. A destination column in this task’s Kanban board is full.",
                bundle: .module,
            )
    }
}
