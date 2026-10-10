@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct DefaultProjectSettingsViewModelTests {
    private func makeViewModel(
        userRepository: FakeUserRepository = FakeUserRepository(),
        projectRepository: FakeProjectRepository = FakeProjectRepository(),
        defaultProjectCache: FakeDefaultProjectCaching = FakeDefaultProjectCaching(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
    ) -> DefaultProjectSettingsViewModel {
        DefaultProjectSettingsViewModel(
            userRepository: userRepository,
            projectRepository: projectRepository,
            defaultProjectCache: defaultProjectCache,
            toastPresenter: toastPresenter,
        )
    }

    // MARK: load

    @Test
    func `load populates projects and the current default project id`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", defaultProjectID: 6))
        let projectRepository = FakeProjectRepository(projects: [
            Project(id: 6, title: "Inbox"),
            Project(id: 7, title: "Work"),
        ])
        let viewModel = makeViewModel(userRepository: userRepository, projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.defaultProjectID == 6)
        #expect(viewModel.defaultProjectTitle == "Inbox")
    }

    @Test
    func `defaultProjectTitle is nil when no default project is set`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", defaultProjectID: nil))
        let projectRepository = FakeProjectRepository(projects: [Project(id: 6, title: "Inbox")])
        let viewModel = makeViewModel(userRepository: userRepository, projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.defaultProjectID == nil)
        #expect(viewModel.defaultProjectTitle == nil)
    }

    @Test
    func `load populates the account time zone from the current user`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", timezone: "Europe/Madrid"))
        let viewModel = makeViewModel(userRepository: userRepository)

        await viewModel.load()

        #expect(viewModel.accountTimezone == "Europe/Madrid")
    }

    @Test
    func `load leaves the account time zone nil when the user has none set`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", timezone: nil))
        let viewModel = makeViewModel(userRepository: userRepository)

        await viewModel.load()

        #expect(viewModel.accountTimezone == nil)
    }

    @Test
    func `load surfaces a failure state when fetching projects fails`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.fetchError = .notFound
        let viewModel = makeViewModel(projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.loadState == .failure(VikunjaError.notFound.displayMessage))
    }

    // MARK: selectDefaultProject

    @Test
    func `selecting a project updates the default project id and the cache`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex"))
        let cache = FakeDefaultProjectCaching()
        let viewModel = makeViewModel(userRepository: userRepository, defaultProjectCache: cache)
        let project = Project(id: 6, title: "Inbox", hexColor: "ff0000")

        await viewModel.selectDefaultProject(project)

        #expect(viewModel.defaultProjectID == 6)
        #expect(userRepository.lastUpdatedDefaultProjectID == 6)
        #expect(cache.cached == CachedDefaultProject(id: 6, title: "Inbox", hexColor: "ff0000"))
    }

    @Test
    func `selecting none clears the default project id and the cache`() async throws {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", defaultProjectID: 6))
        let cache = FakeDefaultProjectCaching()
        let viewModel = makeViewModel(userRepository: userRepository, defaultProjectCache: cache)
        await viewModel.load()

        await viewModel.selectDefaultProject(nil)

        #expect(viewModel.defaultProjectID == nil)
        let lastUpdatedID = try #require(userRepository.lastUpdatedDefaultProjectID)
        #expect(lastUpdatedID == nil)
        #expect(cache.cached == nil)
    }

    @Test
    func `a failed update rolls back to the previous default project and shows a toast`() async {
        let userRepository = FakeUserRepository(user: User(id: 1, username: "alex", defaultProjectID: 6))
        userRepository.updateError = .notFound
        let toastPresenter = FakeToastPresenter()
        let viewModel = makeViewModel(userRepository: userRepository, toastPresenter: toastPresenter)
        await viewModel.load()

        await viewModel.selectDefaultProject(Project(id: 7, title: "Work"))

        #expect(viewModel.defaultProjectID == 6)
        #expect(toastPresenter.shownMessages.count == 1)
    }
}
