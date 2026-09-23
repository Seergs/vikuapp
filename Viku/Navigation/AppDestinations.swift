import Projects
import SwiftUI
import Tasks
import VikuNavigation
import VikunjaCore

/// The single place that maps an `AppRoute` to a concrete screen. Applied once
/// per tab `NavigationStack` in `MainTabView`, this is the app target's job
/// because it's the only module allowed to import every feature package and
/// know about the concrete `VikunjaNetworking`/`VikuAuth` types behind each
/// `make...ViewModel` factory.
extension View {
    func appDestinations(container: AppContainer, account: InstanceAccount) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case let .taskDetail(task, project):
                TaskDetailDestination(container: container, account: account, task: task, project: project)
            case let .projectOverview(project):
                ProjectOverviewDestination(container: container, account: account, project: project)
            }
        }
    }
}

/// Builds and holds `TaskDetailView`'s view model in `@State`, constructed
/// once in `init` rather than inline in the `.navigationDestination(for:)`
/// closure above.
///
/// `.navigationDestination(for:)`'s closure is *not* guaranteed to run only
/// once per push the way its doc comment ("keys off the stable `Hashable`
/// route value") suggests — SwiftUI re-invokes it on unrelated re-renders
/// too (confirmed via logging: a second `TaskDetailViewModel` got constructed,
/// from the route's now-stale captured `task`, mid-edit — right as the first
/// instance's own optimistic mutation triggered a re-render). Calling
/// `container.makeTaskDetailViewModel(...)` directly in that closure, as
/// before, therefore silently swapped in a brand-new, blank view model on
/// unrelated edits: the due-date/priority/label edit looked reverted (the
/// new instance was built from the stale pre-edit task) and comments/
/// attachments vanished (the new instance's own `load()`/`loadComments()`
/// never got a chance to run, since `.task` stays tied to `TaskDetailView`'s
/// position, not to which view model instance is currently passed in).
/// `@State` sidesteps this the same way `MainTabView` already does for its
/// tab view models: `initialValue` only runs the first time this identity's
/// storage is created, so later re-invocations of the closure produce new
/// `TaskDetailDestination` *values* that SwiftUI diffs against the existing
/// one at that position, reusing the already-live view model instead of
/// replacing it.
private struct TaskDetailDestination: View {
    let container: AppContainer
    let account: InstanceAccount
    @State private var viewModel: TaskDetailViewModel

    init(container: AppContainer, account: InstanceAccount, task: VikunjaTask, project: Project) {
        self.container = container
        self.account = account
        _viewModel = State(initialValue: container.makeTaskDetailViewModel(
            task: task,
            project: project,
            account: account,
        ))
    }

    var body: some View {
        TaskDetailView(viewModel: viewModel)
    }
}

/// Same fix as `TaskDetailDestination`, for the same reason: `viewModel`
/// built once in `init` and held in `@State` instead of being reconstructed
/// on every `.navigationDestination(for:)` re-invocation.
private struct ProjectOverviewDestination: View {
    let container: AppContainer
    let account: InstanceAccount
    @State private var viewModel: ProjectOverviewViewModel

    init(container: AppContainer, account: InstanceAccount, project: Project) {
        self.container = container
        self.account = account
        _viewModel = State(initialValue: container.makeProjectOverviewViewModel(project: project, account: account))
    }

    var body: some View {
        ProjectOverviewRootView(
            viewModel: viewModel,
            makeEditProjectViewModel: { container.makeEditProjectViewModel(project: $0, account: account) },
        )
    }
}
