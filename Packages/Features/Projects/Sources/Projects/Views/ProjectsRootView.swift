import SwiftUI
import VikuNavigation
import VikunjaCore

/// Projects' entry point for the app target: the project-list screen plus the
/// feature-local `.navigationDestination(for: ProjectsRoute.self)` for drilling
/// into a project overview. The hosting `NavigationStack` and its `AppRouter`
/// are owned by the app target (`MainTabView`); a task's detail screen is
/// reached by pushing `AppRoute.taskDetail`, resolved by the app target's
/// `.appDestinations(...)` on the same stack.
public struct ProjectsRootView: View {
    @Environment(AppRouter.self) private var router
    private let viewModel: ProjectsListViewModel
    private let makeOverviewViewModel: (ProjectNode) -> ProjectOverviewViewModel
    private let makeCreateProjectViewModel: () -> CreateProjectViewModel
    private let makeEditProjectViewModel: (Project) -> EditProjectViewModel

    /// The `make...ViewModel` closures come from the app target's
    /// `AppContainer`, the only place allowed to know about the concrete
    /// repositories these view models need.
    public init(
        viewModel: ProjectsListViewModel,
        makeOverviewViewModel: @escaping (ProjectNode) -> ProjectOverviewViewModel,
        makeCreateProjectViewModel: @escaping () -> CreateProjectViewModel,
        makeEditProjectViewModel: @escaping (Project) -> EditProjectViewModel,
    ) {
        self.viewModel = viewModel
        self.makeOverviewViewModel = makeOverviewViewModel
        self.makeCreateProjectViewModel = makeCreateProjectViewModel
        self.makeEditProjectViewModel = makeEditProjectViewModel
    }

    @State private var editingProject: Project?

    public var body: some View {
        ProjectsView(
            viewModel: viewModel,
            makeCreateProjectViewModel: makeCreateProjectViewModel,
            makeEditProjectViewModel: makeEditProjectViewModel,
        )
        .navigationDestination(for: ProjectsRoute.self) { route in
            switch route {
            case let .projectOverview(node):
                ProjectOverviewView(
                    viewModel: makeOverviewViewModel(node),
                    onSelectSubproject: { router.push(ProjectsRoute.projectOverview($0)) },
                    onSelectTask: { task in router.push(.taskDetail(task, node.project)) },
                    onEditProject: { editingProject = $0 },
                )
            }
        }
        .sheet(item: $editingProject) { project in
            EditProjectSheetView(viewModel: makeEditProjectViewModel(project))
                .presentationCompactAdaptation(.sheet)
        }
    }
}
