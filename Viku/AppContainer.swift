import CalendarFeature
import Foundation
import Home
import Onboarding
import Projects
import Search
import Settings
import Tasks
import VikuAuth
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikunjaNetworking
import VikuWidgetKit
import WidgetKit

/// Composition root. The only type in the app target allowed to know about
/// concrete `VikunjaNetworking`/`VikuAuth` implementations — it wires them
/// into the `VikunjaCore` protocols each `Features/*` module receives through
/// constructor injection.
@MainActor
final class AppContainer {
    let accountStore: AccountStoreProtocol
    let clientFactory: InstanceClientFactoryProtocol
    /// Resolves a currently-valid bearer credential per account, transparently
    /// refreshing a password-based session's JWT before it expires — every
    /// `tokenProvider` closure below goes through this instead of reading
    /// `accountStore.token(forAccountID:)` directly, so a password account's
    /// session stays alive without any screen needing to know about it. A
    /// no-op passthrough for API-token accounts.
    let sessionRefresher: PasswordSessionRefresher
    /// The single toast host for the whole app — see `RootView`'s
    /// `.toastHost(_:)`. Pass this as `ToastPresenting` to any ViewModel that
    /// needs to surface a toast (e.g. `toastPresenter:` in a `make...ViewModel`
    /// factory below); it never needs to import `VikuDesignSystem` itself.
    let toastCenter = ToastCenter()
    /// The app's single Taptic Engine — see `HapticFeedbackCenter`. Pass this
    /// as `HapticFeedbackPresenting` to any ViewModel that needs to fire a
    /// haptic from its own logic (e.g. add a `hapticPresenter:` parameter to
    /// the relevant `make...ViewModel` factory below, exactly like
    /// `toastPresenter:`); the ViewModel never imports `VikuDesignSystem`.
    /// A purely view-driven tap should use `View.vikuHaptic(_:trigger:)`
    /// instead and needs nothing from here.
    let hapticCenter = HapticFeedbackCenter()
    /// Tracks which project (if any) the visible screen represents, so the
    /// tab-bar quick-add sheet defaults to it — see `QuickAddContext`.
    let quickAddContext = QuickAddContext()
    /// The app's single theme preference (light/dark/automatic), read
    /// directly by `RootView` to drive `.preferredColorScheme(_:)` and passed
    /// to `Settings` as `AppThemeStoring` so it can offer the picker.
    let themeCenter = ThemeCenter()
    /// Carries a `viku://` deep link (or an `OpenQuickAddIntent`) from
    /// `RootView`'s `.onOpenURL` to the screen that acts on it. The shared
    /// instance, so the App Intent's `perform()` reaches the same router.
    let deepLinkRouter = DeepLinkRouter.shared
    /// On-device cache of each account's Vikunja default project, refreshed
    /// once per launch by `refreshDefaultProject(account:)` and read
    /// synchronously by `makeQuickAddTaskViewModel`.
    let defaultProjectStore = DefaultProjectStore()
    /// The app's single OIDC browser-authentication coordinator — see
    /// `OIDCAuthCoordinator`. Pass this as `OIDCAuthenticating` to any
    /// ViewModel that offers OIDC sign-in.
    let oidcAuthCoordinator: OIDCAuthenticating = OIDCAuthCoordinator()
    /// The redirect URI OIDC providers must be configured to allow, alongside
    /// each instance's own web frontend — reuses the app's existing
    /// `viku://`/`viku-dev://` deep-link scheme, so no separate URL scheme
    /// registration is needed.
    let oidcRedirectURI: URL = {
        guard let url = URL(string: "\(VikuWidgetConfig.urlScheme)://oidc-callback") else {
            fatalError("oidc redirect URI scheme is invalid")
        }
        return url
    }()

    init(
        accountStore: AccountStoreProtocol = KeychainAccountStore(
            service: VikuWidgetConfig.accountStoreService,
            accessGroup: VikuWidgetConfig.keychainAccessGroup,
        ),
        clientFactory: InstanceClientFactoryProtocol = VikunjaInstanceClientFactory(),
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.sessionRefresher = PasswordSessionRefresher(accountStore: accountStore)
    }

    /// One-time move of Keychain items written before the shared
    /// `keychain-access-group` existed into that group, so the widget can read
    /// the active account and its token. No-op after the first run, and when
    /// `accountStore` isn't the Keychain-backed one (tests). Call once on launch.
    func bootstrap() async {
        guard let store = accountStore as? KeychainAccountStore else { return }
        try? await store.migrateToAccessGroup()
    }

    /// Fetches the Today and Calendar data with the app's own (always-working)
    /// account store and writes them to the shared App Group caches, then
    /// reloads every widget. This is what makes the widgets work even where
    /// keychain sharing with the extension doesn't (the iOS Simulator, an
    /// un-provisioned build): they render these caches when they can't
    /// authenticate themselves. Call on launch and whenever the app backgrounds.
    func refreshWidgetSnapshots() async {
        let todayLoader = TodaySnapshotLoader(
            accountStore: accountStore,
            clientFactory: clientFactory,
            cache: TodaySnapshotCache(appGroupIdentifier: VikuWidgetConfig.appGroupIdentifier),
        )
        let calendarLoader = CalendarSnapshotLoader(
            accountStore: accountStore,
            clientFactory: clientFactory,
            cache: CalendarSnapshotCache(appGroupIdentifier: VikuWidgetConfig.appGroupIdentifier),
        )
        _ = await todayLoader.loadState()
        _ = await calendarLoader.loadState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Refreshes the cached Vikunja default project for `account` from
    /// `GET /api/v1/user` and writes it to `defaultProjectStore`. Called on
    /// launch and on account switch (see `RootView`) — the only place that
    /// request is made, so quick-add reads the cache instead of hitting the
    /// network every time its sheet opens. A failed fetch leaves the previous
    /// cached value untouched.
    func refreshDefaultProject(account: InstanceAccount) async {
        let userRepository = clientFactory.makeUserRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        guard let user = try? await userRepository.fetchCurrentUser() else { return }
        defaultProjectStore.setProjectID(user.defaultProjectID, forAccountID: account.id)
    }

    func makeInstanceSetupViewModel() -> InstanceSetupViewModel {
        InstanceSetupViewModel(
            accountStore: accountStore,
            clientFactory: clientFactory,
            oidcAuthenticator: oidcAuthCoordinator,
            oidcRedirectURI: oidcRedirectURI,
        )
    }

    func makeTodayViewModel(account: InstanceAccount) -> TodayViewModel {
        let tokenProvider = tokenProvider(for: account)
        return TodayViewModel(
            taskRepository: clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider),
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            ),
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
        )
    }

    func makeCalendarViewModel(account: InstanceAccount) -> CalendarViewModel {
        let tokenProvider = tokenProvider(for: account)
        return CalendarViewModel(
            taskRepository: clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider),
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            ),
            hapticPresenter: hapticCenter,
        )
    }

    func makeProjectsListViewModel(account: InstanceAccount) -> ProjectsListViewModel {
        let tokenProvider = tokenProvider(for: account)
        let repository = clientFactory.makeProjectRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        let taskRepository = clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        return ProjectsListViewModel(
            repository: repository,
            taskRepository: taskRepository,
            toastPresenter: toastCenter,
        )
    }

    func makeCreateProjectViewModel(parentProjectID: Int? = nil, account: InstanceAccount) -> CreateProjectViewModel {
        let repository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        return CreateProjectViewModel(
            parentProjectID: parentProjectID,
            repository: repository,
            toastPresenter: toastCenter,
        )
    }

    func makeEditProjectViewModel(project: Project, account: InstanceAccount) -> EditProjectViewModel {
        let repository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        return EditProjectViewModel(project: project, repository: repository, toastPresenter: toastCenter)
    }

    func makeProjectOverviewViewModel(node: ProjectNode, account: InstanceAccount) -> ProjectOverviewViewModel {
        let tokenProvider = tokenProvider(for: account)
        let repository = clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        let projectRepository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        return ProjectOverviewViewModel(
            project: node.project,
            subprojects: node.children,
            repository: repository,
            projectRepository: projectRepository,
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
            quickAddContext: quickAddContext,
        )
    }

    /// For a project reached from outside the already-loaded projects tree
    /// (`Features/Tasks`' project pill, today) — see `ProjectOverviewRootView`.
    /// No `ProjectNode` is available there, only the bare `Project`, so this
    /// seeds `ProjectOverviewViewModel` with no known subprojects.
    func makeProjectOverviewViewModel(project: Project, account: InstanceAccount) -> ProjectOverviewViewModel {
        makeProjectOverviewViewModel(node: ProjectNode(project: project), account: account)
    }

    func makeTaskDetailViewModel(task: VikunjaTask, project: Project, account: InstanceAccount) -> TaskDetailViewModel {
        let tokenProvider = tokenProvider(for: account)
        let repository = clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        let labelRepository = clientFactory.makeLabelRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        let relationRepository = clientFactory.makeTaskRelationRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        let commentRepository = clientFactory.makeTaskCommentRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        let attachmentRepository = clientFactory.makeTaskAttachmentRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        let projectRepository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        return TaskDetailViewModel(
            task: task,
            project: project,
            repository: repository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            commentRepository: commentRepository,
            attachmentRepository: attachmentRepository,
            projectRepository: projectRepository,
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
            quickAddContext: quickAddContext,
        )
    }

    /// - Parameter preselectedProjectID: snapshotted by the caller (see
    ///   `MainTabView`) at the moment the quick-add sheet is opened — not read
    ///   from `quickAddContext` here, since this factory runs inside a
    ///   SwiftUI view body and an `@Observable` read would rebuild the sheet.
    func makeQuickAddTaskViewModel(
        preselectedProjectID: Int?,
        account: InstanceAccount,
    ) -> QuickAddTaskViewModel {
        let tokenProvider = tokenProvider(for: account)
        return QuickAddTaskViewModel(
            preselectedProjectID: preselectedProjectID,
            accountDefaultProjectID: defaultProjectStore.projectID(forAccountID: account.id),
            taskRepository: clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider),
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            ),
            toastPresenter: toastCenter,
        )
    }

    func makeManageLabelsViewModel(account: InstanceAccount) -> ManageLabelsViewModel {
        let repository = clientFactory.makeLabelRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        return ManageLabelsViewModel(repository: repository, toastPresenter: toastCenter)
    }

    func makeConnectionsListViewModel(onActiveAccountChanged: @escaping () -> Void) -> ConnectionsListViewModel {
        ConnectionsListViewModel(
            accountStore: accountStore,
            clientFactory: clientFactory,
            toastPresenter: toastCenter,
            onActiveAccountChanged: onActiveAccountChanged,
        )
    }

    func makeConnectionFormViewModel(
        mode: ConnectionFormMode,
        onActiveAccountChanged: @escaping () -> Void,
    ) -> ConnectionFormViewModel {
        ConnectionFormViewModel(
            mode: mode,
            accountStore: accountStore,
            clientFactory: clientFactory,
            toastPresenter: toastCenter,
            oidcAuthenticator: oidcAuthCoordinator,
            oidcRedirectURI: oidcRedirectURI,
            onActiveAccountChanged: onActiveAccountChanged,
        )
    }

    func makeSearchViewModel(account: InstanceAccount) -> SearchViewModel {
        let tokenProvider = tokenProvider(for: account)
        return SearchViewModel(
            taskRepository: clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider),
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            ),
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
        )
    }

    /// Builds the `tokenProvider` closure every `make*Repository` call takes
    /// — routes through `sessionRefresher` so a password account's JWT is
    /// refreshed transparently, and an API-token account passes through with
    /// no behavior change.
    private func tokenProvider(for account: InstanceAccount) -> @Sendable () async -> String? {
        let sessionRefresher = sessionRefresher
        return { await sessionRefresher.validToken(for: account) }
    }
}
