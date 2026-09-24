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
    /// A plain reference type, not `@State`, so filling the cache while
    /// building a `navigationDestination` never mutates SwiftUI state mid-
    /// render. It used to be `@State private var overviewViewModels: [Int:
    /// ProjectOverviewViewModel]`, written from that destination's own
    /// `.onAppear` - but that meant the *first* visit to a given project
    /// mutated `@State` as a side effect of the same view-graph update that
    /// was still settling the freshly-pushed `ProjectOverviewView`'s own
    /// `.onAppear` (which calls `markVisible()` for quick-add's project
    /// preselection). SwiftUI docs call mutating `@State` during a view
    /// update undefined behavior, and in practice it could win the race and
    /// clobber that mount before `markVisible()` ran, leaving quick-add
    /// falling back to the account default even while visibly on the
    /// project's page. Caching still exists to avoid losing a
    /// `ProjectOverviewViewModel`'s loaded tasks on back-navigation (see
    /// 451e893), it's just no longer state-driven.
    @State private var overviewViewModelCache = OverviewViewModelCache()

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
                    viewModel: cachedOverviewViewModel(for: node),
                    onSelectSubproject: { router.push(ProjectsRoute.projectOverview($0)) },
                    onSelectTask: { task in router.push(.taskDetail(task, node.project)) },
                    onEditProject: { editingProject = $0 },
                    onDuplicated: { router.push(.taskDetail($0, $1)) },
                )
            }
        }
        .sheet(item: $editingProject) { project in
            EditProjectSheetView(makeViewModel: { makeEditProjectViewModel(project) })
                .presentationCompactAdaptation(.sheet)
        }
    }

    /// Returns this project's cached `ProjectOverviewViewModel`, creating and
    /// storing one on first visit. A plain function call (not a statement
    /// mutating `@State` alongside building the destination view) so it's a
    /// valid `ViewBuilder` expression and, more importantly, so filling the
    /// cache never mutates SwiftUI state mid-render - see
    /// `overviewViewModelCache`'s doc comment.
    private func cachedOverviewViewModel(for node: ProjectNode) -> ProjectOverviewViewModel {
        if let existing = overviewViewModelCache.storage[node.id] {
            return existing
        }
        let vm = makeOverviewViewModel(node)
        overviewViewModelCache.storage[node.id] = vm
        return vm
    }
}

/// Backs `ProjectsRootView.overviewViewModelCache`. A class rather than a
/// struct so `@State` only needs to preserve *its identity* (one instance
/// for the life of the screen) - mutating `storage` doesn't go through
/// `@State`'s setter, so it never triggers a SwiftUI view update.
@MainActor
private final class OverviewViewModelCache {
    var storage: [Int: ProjectOverviewViewModel] = [:]
}
