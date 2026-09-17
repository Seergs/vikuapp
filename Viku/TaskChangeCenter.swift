import Observation
import VikunjaCore

/// The single source of truth for "a task was just created" broadcasts — see
/// `TaskChangeBroadcasting`. Owned by `AppContainer`, injected the same way
/// `QuickAddContext` is.
@MainActor
@Observable
final class TaskChangeCenter: TaskChangeBroadcasting {
    private(set) var lastCreatedTask: TaskCreatedEvent?

    func taskCreated(projectID: Int) {
        lastCreatedTask = TaskCreatedEvent(projectID: projectID)
    }
}
