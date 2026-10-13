@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct HomeSelectionSettingsViewModelTests {
    private func makeViewModel(
        projectRepository: FakeProjectRepository = FakeProjectRepository(),
        store: FakeHomeSelectionCaching = FakeHomeSelectionCaching(),
    ) -> HomeSelectionSettingsViewModel {
        HomeSelectionSettingsViewModel(projectRepository: projectRepository, store: store)
    }

    // MARK: load

    @Test
    func `load populates the project list`() async {
        let projectRepository = FakeProjectRepository(projects: [
            Project(id: 1, title: "Work"),
            Project(id: -2, title: "My Open Tasks"),
        ])
        let viewModel = makeViewModel(projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.projects.map(\.id) == [1, -2])
    }

    @Test
    func `load surfaces a failure state when fetching projects fails`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.fetchError = .notFound
        let viewModel = makeViewModel(projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.loadState == .failure(VikunjaError.notFound.displayMessage))
    }

    // MARK: pickableProjects

    @Test
    func `pickableProjects excludes Favorites and archived projects but keeps saved filters`() async {
        let projectRepository = FakeProjectRepository(projects: [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Archived", isArchived: true),
            Project(id: -1, title: "Favorites"),
            Project(id: -2, title: "My Open Tasks"),
        ])
        let viewModel = makeViewModel(projectRepository: projectRepository)

        await viewModel.load()

        #expect(Set(viewModel.pickableProjects.map(\.id)) == [1, -2])
    }

    // MARK: selectionTitle

    @Test
    func `selectionTitle is Today when nothing is pinned`() {
        let viewModel = makeViewModel()

        #expect(viewModel.selectionTitle == "Today")
    }

    @Test
    func `selectionTitle reflects the cached selection before load resolves`() {
        let cached = CachedHomeSelection(id: -2, title: "My Open Tasks", hexColor: "", kind: .savedFilter)
        let viewModel = makeViewModel(store: FakeHomeSelectionCaching(cached: cached))

        #expect(viewModel.selectionTitle == "My Open Tasks")
    }

    // MARK: select

    @Test
    func `selecting a project pins it and writes through the store`() {
        let store = FakeHomeSelectionCaching()
        let viewModel = makeViewModel(store: store)
        let project = Project(id: 7, title: "Work", hexColor: "00ff00")

        viewModel.select(project)

        #expect(viewModel.selection == CachedHomeSelection(id: 7, title: "Work", hexColor: "00ff00", kind: .project))
        #expect(store.cached == viewModel.selection)
    }

    @Test
    func `selecting a saved filter pins it with the savedFilter kind`() {
        let store = FakeHomeSelectionCaching()
        let viewModel = makeViewModel(store: store)
        let filter = Project(id: -2, title: "My Open Tasks")

        viewModel.select(filter)

        #expect(viewModel.selection?.kind == .savedFilter)
    }

    @Test
    func `selecting nil pins Today and clears the store`() {
        let cached = CachedHomeSelection(id: 7, title: "Work", hexColor: "00ff00", kind: .project)
        let store = FakeHomeSelectionCaching(cached: cached)
        let viewModel = makeViewModel(store: store)

        viewModel.select(nil)

        #expect(viewModel.selection == nil)
        #expect(store.cached == nil)
        #expect(viewModel.selectionTitle == "Today")
    }
}
