@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct DefaultProjectSettingsViewModelTests {
    private func makeViewModel(
        userRepository: FakeUserRepository = FakeUserRepository(),
        projectRepository: FakeProjectRepository = FakeProjectRepository(),
        defaultProjectCache: FakeDefaultProjectCaching = FakeDefaultProjectCaching(),
        timezoneCache: FakeAccountTimezoneCaching = FakeAccountTimezoneCaching(),
        displayNameCache: FakeAccountDisplayNameCaching = FakeAccountDisplayNameCaching(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
    ) -> DefaultProjectSettingsViewModel {
        DefaultProjectSettingsViewModel(
            userRepository: userRepository,
            projectRepository: projectRepository,
            defaultProjectCache: defaultProjectCache,
            timezoneCache: timezoneCache,
            displayNameCache: displayNameCache,
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

    @Test
    func `shows the cached default project title, time zone and display name before load resolves`() {
        let cachedProject = CachedDefaultProject(id: 6, title: "Inbox", hexColor: "ff0000")
        let viewModel = makeViewModel(
            defaultProjectCache: FakeDefaultProjectCaching(cached: cachedProject),
            timezoneCache: FakeAccountTimezoneCaching(cached: "Europe/Madrid"),
            displayNameCache: FakeAccountDisplayNameCaching(cached: "Alex"),
        )

        #expect(viewModel.defaultProjectTitle == "Inbox")
        #expect(viewModel.accountTimezone == "Europe/Madrid")
        #expect(viewModel.accountDisplayName == "Alex")
    }

    @Test
    func `load overwrites the cached title, time zone and display name once it resolves`() async {
        let userRepository = FakeUserRepository(
            user: User(
                id: 1, username: "alex", name: "Alexandra", defaultProjectID: 7, timezone: "America/Mexico_City",
            ),
        )
        let projectRepository = FakeProjectRepository(projects: [Project(id: 7, title: "Work", hexColor: "00ff00")])
        let defaultProjectCache = FakeDefaultProjectCaching(
            cached: CachedDefaultProject(id: 6, title: "Inbox", hexColor: "ff0000"),
        )
        let timezoneCache = FakeAccountTimezoneCaching(cached: "Europe/Madrid")
        let displayNameCache = FakeAccountDisplayNameCaching(cached: "Alex")
        let viewModel = makeViewModel(
            userRepository: userRepository,
            projectRepository: projectRepository,
            defaultProjectCache: defaultProjectCache,
            timezoneCache: timezoneCache,
            displayNameCache: displayNameCache,
        )

        await viewModel.load()

        #expect(viewModel.defaultProjectTitle == "Work")
        #expect(viewModel.accountTimezone == "America/Mexico_City")
        #expect(viewModel.accountDisplayName == "Alexandra")
        #expect(defaultProjectCache.cached == CachedDefaultProject(id: 7, title: "Work", hexColor: "00ff00"))
        #expect(timezoneCache.cached == "America/Mexico_City")
        #expect(displayNameCache.cached == "Alexandra")
    }

    @Test
    func `a failed load keeps showing the cached title, time zone and display name`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.fetchError = .notFound
        let viewModel = makeViewModel(
            projectRepository: projectRepository,
            defaultProjectCache: FakeDefaultProjectCaching(
                cached: CachedDefaultProject(id: 6, title: "Inbox", hexColor: "ff0000"),
            ),
            timezoneCache: FakeAccountTimezoneCaching(cached: "Europe/Madrid"),
            displayNameCache: FakeAccountDisplayNameCaching(cached: "Alex"),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failure(VikunjaError.notFound.displayMessage))
        #expect(viewModel.defaultProjectTitle == "Inbox")
        #expect(viewModel.accountTimezone == "Europe/Madrid")
        #expect(viewModel.accountDisplayName == "Alex")
    }

    // MARK: pickableProjects

    @Test
    func `pickableProjects excludes favorites, saved filters and archived projects`() async {
        let projectRepository = FakeProjectRepository(projects: [
            Project(id: 6, title: "Inbox"),
            Project(id: -1, title: "Favorites"),
            Project(id: -2, title: "My Open Tasks"),
            Project(id: 7, title: "Done", isArchived: true),
        ])
        let viewModel = makeViewModel(projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.pickableProjects.map(\.id) == [6])
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
