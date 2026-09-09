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
///
/// Because `.navigationDestination(for:)` keys off the stable `Hashable`
/// `AppRoute` value already sitting in the `NavigationPath`, the pushed screen
/// and its view model survive re-renders - this is what replaced the
/// `(T) -> AnyView` closures and the `...DestinationBox` identity workarounds
/// (architecture audit F-12).
extension View {
    func appDestinations(container: AppContainer, account: InstanceAccount) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case let .taskDetail(task, project):
                TaskDetailView(
                    viewModel: container.makeTaskDetailViewModel(
                        task: task,
                        project: project,
                        account: account,
                    ),
                )
            case let .projectOverview(project):
                ProjectOverviewRootView(
                    viewModel: container.makeProjectOverviewViewModel(project: project, account: account),
                    makeEditProjectViewModel: { container.makeEditProjectViewModel(project: $0, account: account) },
                )
            }
        }
    }
}
