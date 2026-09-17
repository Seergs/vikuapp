import Foundation

/// One task-created broadcast. `token` makes every event distinct even when
/// two tasks are created into the same project back to back, so an
/// `Equatable`-driven observer (`.onChange(of:)`) fires on every single
/// creation rather than only the first.
public struct TaskCreatedEvent: Equatable, Sendable {
    public let projectID: Int
    private let token: UUID

    public init(projectID: Int) {
        self.projectID = projectID
        self.token = UUID()
    }
}

/// Lets a project-scoped screen learn that a task was created for it
/// somewhere else in the app (currently: the tab-bar quick-add sheet), so it
/// can refresh its list live instead of only on the next pull-to-refresh.
///
/// Implemented by the app target (`TaskChangeCenter`) and injected the same
/// way `QuickAddContextTracking` is.
@MainActor
public protocol TaskChangeBroadcasting: AnyObject {
    func taskCreated(projectID: Int)
    var lastCreatedTask: TaskCreatedEvent? { get }
}
