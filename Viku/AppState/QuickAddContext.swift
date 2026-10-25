import Observation
import VikunjaCore

/// The single source of truth for "which project should the tab-bar quick-add
/// sheet default to". Project-scoped screens (a project overview, a task's
/// detail) push their project id while visible via
/// `ProjectOverviewViewModel`/`TaskDetailViewModel`'s `markVisible()` /
/// `markHidden()`; `MainTabView` snapshots `preselectedProjectID` when the FAB
/// is tapped and hands it to `AppContainer.makeQuickAddTaskViewModel`. `nil`
/// means "use the account's default project" (`User.defaultProjectID`).
///
/// The active scopes are a stack, not one value — see `QuickAddContextTracking`
/// for why. Owned by `AppContainer`, injected as `QuickAddContextTracking` the
/// same way `ToastCenter` is injected as `ToastPresenting`.
@MainActor
@Observable
final class QuickAddContext: QuickAddContextTracking {
    private var scopes: [Project] = []

    var preselectedProjectID: Int? {
        scopes.last?.id.remoteValue
    }

    var preselectedProject: Project? {
        scopes.last
    }

    func enterProjectScope(_ project: Project) {
        scopes.append(project)
    }

    func exitProjectScope(_ projectID: Int) {
        if let index = scopes.lastIndex(where: { $0.id.remoteValue == projectID }) {
            scopes.remove(at: index)
        }
    }
}
