import Foundation

/// A lightweight reference to another task, used for `VikunjaTask.subtasks`,
/// `dependsOn`, and `blocks`. Vikunja represents all of these the same way —
/// a "related task" keyed by relation kind — so this stays a thin summary
/// (not a full recursive `VikunjaTask`) rather than embedding an entire task
/// graph.
public struct TaskRelation: Identifiable, Equatable, Hashable, Sendable {
    public let id: EntityID
    public var title: String
    public var isDone: Bool
    public var projectID: EntityID

    public init(id: EntityID, title: String, isDone: Bool = false, projectID: EntityID) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.projectID = projectID
    }
}
