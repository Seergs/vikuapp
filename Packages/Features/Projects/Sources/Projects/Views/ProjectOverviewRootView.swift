import SwiftUI
import VikuNavigation
import VikunjaCore

/// A single project's overview, pushed as a leaf from another feature's stack
/// (Tasks, today, via `AppRoute.projectOverview` from a task's project pill)
/// rather than reached by walking `ProjectsRootView`'s own list.
///
/// It owns no `NavigationStack` of its own and reaches navigation through
/// `@Environment(AppRouter.self)`, like every screen: a subproject or one of
/// this project's tasks pushes another `AppRoute` onto the hosting stack,
/// resolved by the app target's `.appDestinations(...)`.
///
/// The seed `viewModel` here was built from a bare `Project` rather than a
/// `ProjectNode` from an already-loaded tree (the caller doesn't have one),
/// so its `subprojects` is empty and the "Subprojects" section simply doesn't
/// render - acceptable for a screen reached from outside Projects, where
/// seeing this project's own tasks is the point.
public struct ProjectOverviewRootView: View {
    @Environment(AppRouter.self) private var router
    private let viewModel: ProjectOverviewViewModel
    private let makeEditProjectViewModel: (Project) -> EditProjectViewModel
    @State private var editingProject: Project?

    public init(
        viewModel: ProjectOverviewViewModel,
        makeEditProjectViewModel: @escaping (Project) -> EditProjectViewModel,
    ) {
        self.viewModel = viewModel
        self.makeEditProjectViewModel = makeEditProjectViewModel
    }

    public var body: some View {
        ProjectOverviewView(
            viewModel: viewModel,
            onSelectSubproject: { router.push(.projectOverview($0.project)) },
            onSelectTask: { router.push(.taskDetail($0, viewModel.project)) },
            onEditProject: { editingProject = $0 },
        )
        // Pushed from a `.inline`-titled screen (Tasks' `TaskDetailView`), a
        // pushed screen inherits that inline mode by default - force the large
        // title so this looks the same as reaching the project from its own
        // tab.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        // `EditProjectSheetView` is a `.sheet` (not a route push), so this
        // screen can present it without owning a `Router` - matching how
        // `ProjectsRootView` wires the same edit button.
        .sheet(item: $editingProject) { project in
            EditProjectSheetView(viewModel: makeEditProjectViewModel(project))
                .presentationCompactAdaptation(.sheet)
        }
    }
}
