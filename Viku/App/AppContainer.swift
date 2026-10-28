import CalendarFeature
import Foundation
import Home
import Kanban
import Onboarding
import Projects
import Search
import Settings
import Tasks
import UIKit
import VikuAuth
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikunjaNetworking
import VikunjaPersistence
import VikuWidgetKit
import WidgetKit

/// Composition root. The only type in the app target allowed to know about
/// concrete `VikunjaNetworking`/`VikuAuth`/`VikunjaPersistence` implementations
/// — it wires them into the `VikunjaCore` protocols each `Features/*` module
/// receives through constructor injection.
@MainActor
final class AppContainer {
    let accountStore: AccountStoreProtocol
    let clientFactory: InstanceClientFactoryProtocol
    /// Every saved account's offline cache (projects, their mutation queue,
    /// sync bookkeeping) in one shared SQLite database — see `LocalStore`.
    /// Falls back to the app's own Application Support directory when the
    /// App Group container isn't available (an unprovisioned Simulator
    /// build), the same way every other on-device cache in this app
    /// degrades rather than crashing.
    let localStore: LocalStore = AppContainer.makeLocalStore()
    /// Shared by `syncCoordinator` and every `OfflineProjectRepository` this
    /// container builds, so they agree on whether the network is up right
    /// now.
    let reachabilityMonitor: ReachabilityMonitoring = NWPathReachabilityMonitor()
    /// Keeps every saved account's offline queue draining and local cache
    /// refreshed whenever the network is reachable, independent of which
    /// account is currently active — see `SyncCoordinator`. Started once in
    /// `bootstrap()`.
    let syncCoordinator: SyncCoordinator
    /// Resolves a currently-valid bearer credential per account, transparently
    /// refreshing a password-based session's JWT before it expires — every
    /// `tokenProvider` closure below goes through this instead of reading
    /// `accountStore.token(forAccountID:)` directly, so a password account's
    /// session stays alive without any screen needing to know about it. A
    /// no-op passthrough for API-token accounts.
    let sessionRefresher: PasswordSessionRefresher
    /// Live notification that an account's session can no longer be
    /// renewed — `MainTabView` observes this to prompt the user to sign in
    /// again. See `SessionExpiryCenter`.
    let sessionExpiryCenter = SessionExpiryCenter()
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
    /// Broadcasts "a task was created" so a project-scoped screen can refresh
    /// live when the quick-add sheet creates a task for it — see
    /// `TaskChangeCenter`.
    let taskChangeCenter = TaskChangeCenter()
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
    /// On-device cache of each account's Vikunja time zone, backing
    /// `DefaultProjectSettingsViewModel`'s "Time Zone" row the same way
    /// `defaultProjectStore` backs its "Default Project" row.
    let accountTimezoneStore = AccountTimezoneStore()
    /// On-device cache of each account's display name, backing the avatar
    /// initials shown on the Settings landing screen the same way
    /// `accountTimezoneStore` backs its "Time Zone" row.
    let accountDisplayNameStore = AccountDisplayNameStore()
    /// On-device cache of each account's signed-in user, so an offline-created
    /// comment can show its real author without a network round trip.
    let currentUserStore = CurrentUserStore()
    /// On-device cache of each account's last known per-project
    /// task-completion tallies, shown instantly on the Projects list before
    /// each project's own count request resolves.
    let projectTaskSummaryStore = ProjectTaskSummaryStore()
    /// On-device cache of each account's last known Vikunja server version,
    /// shown instantly on the Connections screen before each account's own
    /// probe resolves. See `ServerVersionStore`.
    let serverVersionStore: ServerVersionCaching = ServerVersionStore()
    /// On-device storage of the project or saved filter pinned as the Home
    /// tab's content, backing Settings' "Home Screen" row. Unlike
    /// `defaultProjectStore`, this one has no server-side value to
    /// reconcile against — it's the pin's only source of truth.
    let homeSelectionStore = HomeSelectionStore()
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

    /// The app's single task sort preference store, read/written by project
    /// overview view models.
    let taskSortStore: TaskSortStore = TaskSortCenter()

    /// The shortcut dialect quick-add parses with, chosen in Settings.
    let quickAddSyntaxStore: QuickAddSyntaxStore = QuickAddSyntaxCenter()

    /// Session-only dev-tools state (currently just whether the "DEV" badge
    /// overlay is shown) — see `DevToolsCenter`. Passed to `Settings` as
    /// `DevBadgeVisibilityStoring`, the same way `themeCenter` is passed as
    /// `AppThemeStoring`.
    let devToolsCenter = DevToolsCenter()
    /// On-device record of which "What's New" release this device has
    /// already shown — see `WhatsNewSeenVersionStore`. Passed to `Settings`
    /// as `WhatsNewSeenVersionStoring` so its Developer section can offer a
    /// reset, for re-triggering the sheet during manual testing.
    let whatsNewSeenVersionStore: WhatsNewSeenVersionStoring = WhatsNewSeenVersionStore()
    /// Decides whether there's a "What's New" release to present right now
    /// — see `WhatsNewPresentationResolver`. Built in `init` (not a default
    /// value) so it can share `whatsNewSeenVersionStore` above rather than
    /// a second store instance. `RootView` is the only caller; go through
    /// `whatsNewContentToPresent(hasCompletedOnboarding:)` below rather
    /// than this directly, so the current app version and the Debug-only
    /// minimum-version bypass stay in one place.
    private let whatsNewPresentationResolver: WhatsNewPresentationResolver
    /// Requests notification authorization, obtains the APNs device token,
    /// and registers it with the push relay — see `PushNotificationCoordinator`.
    /// Pass this as `PushNotificationRegistering` to any ViewModel that
    /// offers the notifications opt-in (the consent modal confirms before
    /// calling `enable(vikunjaUserID:)`).
    let pushNotificationRegistering: PushNotificationRegistering = PushNotificationCoordinator()
    /// The user's notification preferences (master switch, user-level
    /// toggle, enabled projects/events) — see `NotificationSettingsCenter`.
    /// Pass this as `NotificationSettingsStore` to `makeNotificationsViewModel`.
    let notificationSettingsStore: NotificationSettingsStore = NotificationSettingsCenter()
    /// Device-wide preference for whether overdue-task pushes arrive as one
    /// combined push instead of one per task — see
    /// `GroupOverdueNotificationsStoring`'s doc comment for why this is a
    /// single store, not one more dictionary on `notificationSettingsStore`.
    /// Pass this as `GroupOverdueNotificationsStoring` to
    /// `makeGroupOverdueNotificationsViewModel` and `makeNotificationsViewModel`
    /// (which only reads it, to apply it to the one account it was built
    /// for); also read directly below so a newly (or already) enabled
    /// account's relay registration is kept in sync with it, not just a
    /// freshly toggled one.
    let groupOverdueNotificationsStore: GroupOverdueNotificationsStoring = GroupOverdueNotificationsStore()
    /// The user's app-icon-badge preference, and the only thing that calls
    /// `setBadgeCount` — see `AppIconBadgeCenter`. Kept as the concrete type
    /// (not just `AppIconBadgeStoring`) since `refreshWidgetSnapshots()`
    /// below calls its `updateBadge(from:)`, which isn't part of that
    /// protocol.
    let appIconBadgeCenter = AppIconBadgeCenter()
    /// Requests the OS authorization the app icon badge needs — shared with
    /// push notifications, since iOS exposes one combined permission. Pass
    /// this as `AppIconBadgePermissionRequesting` to `makeAppIconBadgeViewModel`.
    let appIconBadgePermissionRequester: AppIconBadgePermissionRequesting = APNsPermissionCenter.shared
    /// Tracks the OS run-time extension requested by
    /// `refreshWidgetSnapshotsBeforeSuspension()` so it can be ended exactly
    /// once, from whichever of (refresh finished, OS revoked the extension)
    /// happens first.
    private var widgetRefreshBackgroundTaskID = UIBackgroundTaskIdentifier.invalid

    init(
        accountStore: AccountStoreProtocol = KeychainAccountStore(
            service: VikuWidgetConfig.accountStoreService,
            accessGroup: VikuWidgetConfig.keychainAccessGroup,
        ),
        clientFactory: InstanceClientFactoryProtocol = VikunjaInstanceClientFactory(),
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        let sessionRefresher = PasswordSessionRefresher(
            accountStore: accountStore,
            sessionExpiryReporter: sessionExpiryCenter,
        )
        self.sessionRefresher = sessionRefresher
        self.syncCoordinator = SyncCoordinator(
            localStore: localStore,
            accountStore: accountStore,
            clientFactory: clientFactory,
            reachability: reachabilityMonitor,
            tokenProvider: { account in { try await sessionRefresher.validToken(for: account) } },
        )
        self.whatsNewPresentationResolver = WhatsNewPresentationResolver(
            contentProvider: BundledWhatsNewContentProvider(),
            seenVersionStore: whatsNewSeenVersionStore,
        )
    }

    /// Opens the shared offline database, preferring the App Group
    /// container (so the widget extensions read the same data as their
    /// fallback) and falling back to this app's own Application Support
    /// directory when that container isn't available.
    private static func makeLocalStore() -> LocalStore {
        if let store = try? LocalStore(appGroupIdentifier: VikuWidgetConfig.appGroupIdentifier) {
            return store
        }
        let fallbackDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VikunjaPersistence", isDirectory: true)
        guard let store = try? LocalStore(directory: fallbackDirectory) else {
            fatalError("LocalStore: failed to open the local database in the App Group container or the fallback")
        }
        return store
    }

    /// One-time move of Keychain items written before the shared
    /// `keychain-access-group` existed into that group, so the widget can read
    /// the active account and its token. No-op after the first run, and when
    /// `accountStore` isn't the Keychain-backed one (tests). Also starts
    /// `syncCoordinator` observing reachability. Call once on launch.
    func bootstrap() async {
        await syncCoordinator.start()
        guard let store = accountStore as? KeychainAccountStore else { return }
        try? await store.migrateToAccessGroup()
    }

    /// `hasCompletedOnboarding: false` only from the exact call site where
    /// `connectedAccount` was just created by onboarding, never a returning
    /// launch — see `WhatsNewPresentationResolver`'s doc comment for why
    /// that's what keeps a fresh install from ever seeing content that
    /// predates its own first launch.
    func whatsNewContentToPresent(hasCompletedOnboarding: Bool) -> WhatsNewContent? {
        #if DEBUG
        let bypassMinimumVersion = true
        #else
        let bypassMinimumVersion = false
        #endif
        let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return whatsNewPresentationResolver.contentToPresent(
            locale: .current,
            currentAppVersion: currentAppVersion,
            hasCompletedOnboarding: hasCompletedOnboarding,
            bypassMinimumVersion: bypassMinimumVersion,
        )
    }

    /// Fetches the Today and Calendar data with the app's own (always-working)
    /// account store, then reloads every widget. The widgets read the same
    /// shared offline database as their fallback, so this only keeps the icon
    /// badge and timeline reload prompt when the app backgrounds. Call on
    /// launch and whenever the app backgrounds.
    func refreshWidgetSnapshots() async {
        let sessionRefresher = sessionRefresher
        let resolver: @Sendable (InstanceAccount) async throws -> String? = {
            try await sessionRefresher.validToken(for: $0)
        }
        let localSnapshotProvider = LocalStoreWidgetSnapshotProvider(localStore: localStore)
        let todayLoader = TodaySnapshotLoader(
            accountStore: accountStore,
            clientFactory: clientFactory,
            localSnapshotProvider: localSnapshotProvider,
            tokenResolver: resolver,
        )
        let calendarLoader = CalendarSnapshotLoader(
            accountStore: accountStore,
            clientFactory: clientFactory,
            localSnapshotProvider: localSnapshotProvider,
            tokenResolver: resolver,
        )
        // Apply the last synced count right away: the local database read has
        // no network, so the icon reflects *something* current even if the
        // live fetch below never gets to finish (e.g. the app gets suspended
        // mid-fetch right after entering the background).
        if let localState = await todayLoader.loadLocalState() {
            await appIconBadgeCenter.updateBadge(from: localState)
        }
        let todayState = await todayLoader.loadState()
        _ = await calendarLoader.loadState()
        WidgetCenter.shared.reloadAllTimelines()
        // Reuses the fetch above instead of hitting the network again just
        // for the badge. Overwrites the optimistic value set above once
        // fresh data has actually landed.
        await appIconBadgeCenter.updateBadge(from: todayState)
    }

    /// Same refresh as `refreshWidgetSnapshots()`, but requests extra run
    /// time from the OS first. Call this instead of a plain
    /// `Task { await refreshWidgetSnapshots() }` from a `scenePhase ==
    /// .background` transition: without it, iOS can suspend the app before
    /// the network fetch inside `refreshWidgetSnapshots()` finishes, so the
    /// live badge/widget update silently never runs.
    func refreshWidgetSnapshotsBeforeSuspension() {
        endWidgetRefreshBackgroundTask()
        widgetRefreshBackgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "RefreshWidgetSnapshots",
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endWidgetRefreshBackgroundTask()
            }
        }
        Task {
            await refreshWidgetSnapshots()
            endWidgetRefreshBackgroundTask()
        }
    }

    private func endWidgetRefreshBackgroundTask() {
        guard widgetRefreshBackgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(widgetRefreshBackgroundTaskID)
        widgetRefreshBackgroundTaskID = .invalid
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
        currentUserStore.setUser(user, for: account.id)
        defaultProjectStore.setProjectID(user.defaultProjectID, forAccountID: account.id)
    }

    /// Reconciles every saved account's webhooks with its own stored
    /// notification settings on launch — notifications can be enabled on
    /// several accounts at once, each reconciled independently, so one
    /// account's failure never blocks another's. Call once on launch, not
    /// on every foreground (see `syncNotificationWebhooks`).
    func syncNotificationWebhooksForAllAccounts() async {
        guard let accounts = try? await accountStore.fetchAccounts() else { return }
        for account in accounts {
            await syncNotificationWebhooks(account: account)
        }
    }

    /// Reconciles this account's webhooks with its stored notification
    /// settings — see `WebhookSyncCoordinator`. A no-op when notifications
    /// aren't enabled for this account: this never registers for push on
    /// its own, only re-confirms a registration the user already opted into
    /// (`Features/Settings`' Notifications screen). The relay rate-limits
    /// registrations (5/min, burst 5), and re-registering that often isn't
    /// needed anyway: Apple's own guidance for the device token is to
    /// re-register on every launch, not every foreground. Every failure is
    /// silent and leaves the stored settings untouched; the next launch
    /// retries from the same state.
    func syncNotificationWebhooks(account: InstanceAccount) async {
        guard notificationSettingsStore.settings(for: account.id).isEnabled else { return }

        let tokenProvider = tokenProvider(for: account)
        let userRepository = clientFactory.makeUserRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        guard let user = try? await userRepository.fetchCurrentUser() else { return }
        currentUserStore.setUser(user, for: account.id)
        guard let registration = try? await pushNotificationRegistering.enable(
            vikunjaUserID: user.id,
            accountID: account.id,
        ) else { return }

        // Re-applies the device's current group-overdue preference on every
        // launch, not just the first time this account enables push: this is
        // what makes a newly connected account inherit the setting instead
        // of defaulting to one-push-per-task until the user happens to
        // retoggle it, and self-heals a PATCH that silently failed earlier
        // (see `NotificationsViewModel.setGroupOverdueNotificationsEnabled`,
        // which fails the same way, silently).
        try? await pushNotificationRegistering.updatePreferences(
            groupOverdueNotifications: groupOverdueNotificationsStore.isEnabled,
            accountID: account.id,
        )

        let projectRepository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        guard let projects = try? await projectRepository.fetchProjects() else { return }

        // Drop ids for projects that no longer exist (e.g. deleted after
        // being enabled), so the planner never tries to recreate a webhook
        // for a project that's gone.
        var settings = notificationSettingsStore.settings(for: account.id)
        let validProjectIDs = Set(projects.compactMap(\.id.remoteValue))
        let prunedProjectEvents = settings.projectEvents.filter { validProjectIDs.contains($0.key) }
        if prunedProjectEvents.count != settings.projectEvents.count {
            settings.projectEvents = prunedProjectEvents
            notificationSettingsStore.save(settings, for: account.id)
        }

        let webhookRepository = clientFactory.makeWebhookRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        let coordinator = WebhookSyncCoordinator(webhookRepository: webhookRepository)
        try? await coordinator.sync(settings: settings, registration: registration, projects: projects)
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
        TodayViewModel(
            taskRepository: offlineTaskRepository(for: account),
            projectRepository: offlineProjectRepository(for: account),
            labelRepository: offlineLabelRepository(for: account),
            relationRepository: offlineTaskRelationRepository(for: account),
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
            homeSelectionCache: AccountHomeSelectionCache(store: homeSelectionStore, accountID: account.id),
        )
    }

    func makeCalendarViewModel(account: InstanceAccount) -> CalendarViewModel {
        let tokenProvider = tokenProvider(for: account)
        return CalendarViewModel(
            taskRepository: offlineTaskRepository(for: account),
            projectRepository: offlineProjectRepository(for: account),
            hapticPresenter: hapticCenter,
        )
    }

    func makeProjectsListViewModel(account: InstanceAccount) -> ProjectsListViewModel {
        let tokenProvider = tokenProvider(for: account)
        let repository = offlineProjectRepository(for: account)
        let taskRepository = offlineTaskRepository(for: account)
        let filterRepository = clientFactory.makeFilterRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        return ProjectsListViewModel(
            repository: repository,
            taskRepository: taskRepository,
            filterRepository: filterRepository,
            taskSummaryCache: AccountProjectTaskSummaryCache(store: projectTaskSummaryStore, accountID: account.id),
            toastPresenter: toastCenter,
        )
    }

    func makeCreateProjectViewModel(
        parentProjectID: EntityID? = nil,
        account: InstanceAccount,
    ) -> CreateProjectViewModel {
        let repository = offlineProjectRepository(for: account)
        return CreateProjectViewModel(
            parentProjectID: parentProjectID,
            repository: repository,
            toastPresenter: toastCenter,
        )
    }

    func makeEditProjectViewModel(project: Project, account: InstanceAccount) -> EditProjectViewModel {
        let repository = offlineProjectRepository(for: account)
        return EditProjectViewModel(project: project, repository: repository, toastPresenter: toastCenter)
    }

    func makeRenameFilterViewModel(project: Project, account: InstanceAccount) -> RenameFilterViewModel {
        let repository = clientFactory.makeFilterRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        return RenameFilterViewModel(project: project, repository: repository, toastPresenter: toastCenter)
    }

    func makeProjectOverviewViewModel(node: ProjectNode, account: InstanceAccount) -> ProjectOverviewViewModel {
        let tokenProvider = tokenProvider(for: account)
        let repository = offlineTaskRepository(for: account)
        let projectRepository = offlineProjectRepository(for: account)
        let labelRepository = offlineLabelRepository(for: account)
        let relationRepository = offlineTaskRelationRepository(for: account)
        let filterRepository = clientFactory.makeFilterRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        return ProjectOverviewViewModel(
            project: node.project,
            subprojects: node.children,
            repository: repository,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            filterRepository: filterRepository,
            capabilityProvider: clientFactory.makeCapabilityProvider(baseURL: account.baseURL),
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
            taskSortStore: taskSortStore,
            quickAddContext: quickAddContext,
            taskChangeBroadcaster: taskChangeCenter,
        )
    }

    /// For a project reached from outside the already-loaded projects tree
    /// (`Features/Tasks`' project pill, today) — see `ProjectOverviewRootView`.
    /// No `ProjectNode` is available there, only the bare `Project`, so this
    /// seeds `ProjectOverviewViewModel` with no known subprojects.
    func makeProjectOverviewViewModel(project: Project, account: InstanceAccount) -> ProjectOverviewViewModel {
        makeProjectOverviewViewModel(node: ProjectNode(project: project), account: account)
    }

    /// No v1/v2 switch to pick a repository from — `BucketRepositoryProtocol`
    /// is v2-only (see `VikunjaInstanceClientFactory.makeBucketRepository`).
    /// `ProjectOverviewView` itself gates the Kanban toggle on
    /// `CapabilityProvider.supports(.apiV2)` before this view model's board
    /// ever loads.
    func makeKanbanBoardViewModel(project: Project, account: InstanceAccount) -> KanbanBoardViewModel {
        let repository = clientFactory.makeBucketRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        return KanbanBoardViewModel(
            project: project,
            repository: repository,
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
        )
    }

    func makeTaskDetailViewModel(task: VikunjaTask, project: Project, account: InstanceAccount) -> TaskDetailViewModel {
        let tokenProvider = tokenProvider(for: account)
        let repository = offlineTaskRepository(for: account)
        let labelRepository = offlineLabelRepository(for: account)
        let relationRepository = offlineTaskRelationRepository(for: account)
        let commentRepository = offlineTaskCommentRepository(for: account)
        let attachmentRepository = clientFactory.makeTaskAttachmentRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider,
        )
        let projectRepository = offlineProjectRepository(for: account)
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
            notificationSettingsStore: notificationSettingsStore,
            accountID: account.id,
        )
    }

    /// Resolves a tapped push notification's `task_id` into the task and its
    /// project, for `MainTabView.handleTaskDeepLink`. Only ever called for
    /// `account` already confirmed to be the push's target account — a
    /// mismatch is handled before this by showing a toast instead (switching
    /// accounts automatically is not built yet).
    func resolveTaskDeepLink(id: Int, account: InstanceAccount) async throws -> (VikunjaTask, Project) {
        let tokenProvider = tokenProvider(for: account)
        let taskRepository = offlineTaskRepository(for: account)
        let projectRepository = offlineProjectRepository(for: account)
        let task = try await taskRepository.fetchTask(id: .remote(id))
        let project = try await projectRepository.fetchProject(id: task.projectID)
        return (task, project)
    }

    /// Performs a push notification action button's effect (e.g. "Snooze 1h"
    /// on a fired reminder, "Due Tomorrow" on an overdue task) without
    /// opening the app -- called from `AppDelegate.userNotificationCenter(_:didReceive:)`
    /// for any `actionIdentifier` other than a plain tap. `accountKey` is the
    /// push payload's `account_key` (`InstanceAccount.id.uuidString`),
    /// resolved against every saved account rather than just the active one,
    /// since this can run with no screen -- and no "active account" the user
    /// is looking at -- open at all. A silent no-op if the account is no
    /// longer saved or the action identifier is unrecognized, since there's
    /// no UI here to surface an error to.
    func performNotificationAction(_ actionIdentifier: String, taskID: Int, accountKey: String) async throws {
        guard let accounts = try? await accountStore.fetchAccounts(),
              let account = accounts.first(where: { $0.id.uuidString == accountKey })
        else { return }

        let tokenProvider = tokenProvider(for: account)
        let taskRepository = offlineTaskRepository(for: account)
        var task = try await taskRepository.fetchTask(id: .remote(taskID))

        switch actionIdentifier {
        case PushNotificationActionIdentifier.snoozeReminderOneHour:
            snoozeReminder(on: &task, by: 60 * 60)
        case PushNotificationActionIdentifier.snoozeReminderThreeHours:
            snoozeReminder(on: &task, by: 3 * 60 * 60)
        case PushNotificationActionIdentifier.snoozeReminderOneDay:
            snoozeReminder(on: &task, by: 24 * 60 * 60)
        case PushNotificationActionIdentifier.rescheduleDueTomorrow:
            task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        case PushNotificationActionIdentifier.rescheduleDueNextWeek:
            task.dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        case PushNotificationActionIdentifier.markTaskDone:
            // Always sets done rather than toggling: the task's actual state
            // isn't known until the fetch above lands, and "mark done" from
            // a notification should never risk un-completing a task someone
            // already finished elsewhere.
            task.isDone = true
        default:
            return
        }

        _ = try await taskRepository.update(task)
    }

    /// Bumps the reminder that just fired (the one at or before now, or the
    /// soonest one if none qualifies) an hour out, converting it to an
    /// absolute reminder in the process. It must drop `relativeTo` rather
    /// than just moving `reminder`: go-vikunja recomputes a relative
    /// reminder's absolute time from the task's due/start/end date on every
    /// single update, including the one `performNotificationAction` is about
    /// to send, which would silently undo the snooze on arrival otherwise.
    private func snoozeReminder(on task: inout VikunjaTask, by duration: TimeInterval) {
        let now = Date()
        let index = task.reminders.firstIndex(where: { $0.reminder <= now })
            ?? task.reminders.indices.min(by: { task.reminders[$0].reminder < task.reminders[$1].reminder })
        guard let index else { return }
        task.reminders[index] = TaskReminder(reminder: now.addingTimeInterval(duration))
    }

    /// - Parameters:
    ///   - preselectedProjectID: snapshotted by the caller (see
    ///     `MainTabView`) at the moment the quick-add sheet is opened — not
    ///     read from `quickAddContext` here, since this factory runs inside a
    ///     SwiftUI view body and an `@Observable` read would rebuild the sheet.
    ///   - preselectedProject: the full project behind that id, snapshotted
    ///     the same way, so the sheet can show it immediately instead of a
    ///     spinner (see `QuickAddTaskViewModel.displayProject`).
    func makeQuickAddTaskViewModel(
        preselectedProjectID: EntityID?,
        preselectedProject: Project?,
        account: InstanceAccount,
    ) -> QuickAddTaskViewModel {
        let tokenProvider = tokenProvider(for: account)
        return QuickAddTaskViewModel(
            preselectedProjectID: preselectedProjectID,
            preselectedProject: preselectedProject,
            accountDefaultProjectID: defaultProjectStore.projectID(forAccountID: account.id),
            taskRepository: offlineTaskRepository(for: account),
            projectRepository: offlineProjectRepository(for: account),
            toastPresenter: toastCenter,
            taskChangeBroadcaster: taskChangeCenter,
            syntaxStore: quickAddSyntaxStore,
            labelRepository: offlineLabelRepository(for: account),
            defaultProjectCache: AccountDefaultProjectCache(store: defaultProjectStore, accountID: account.id),
        )
    }

    func makeManageLabelsViewModel(account: InstanceAccount) -> ManageLabelsViewModel {
        ManageLabelsViewModel(repository: offlineLabelRepository(for: account), toastPresenter: toastCenter)
    }

    func makeNotificationsViewModel(account: InstanceAccount) -> NotificationsViewModel {
        let tokenProvider = tokenProvider(for: account)
        return NotificationsViewModel(
            accountID: account.id,
            webhookRepository: clientFactory.makeWebhookRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            ),
            projectRepository: offlineProjectRepository(for: account),
            userRepository: clientFactory.makeUserRepository(baseURL: account.baseURL, tokenProvider: tokenProvider),
            pushNotificationRegistering: pushNotificationRegistering,
            notificationSettingsStore: notificationSettingsStore,
            groupOverdueNotificationsStore: groupOverdueNotificationsStore,
            toastPresenter: toastCenter,
        )
    }

    func makeAppIconBadgeViewModel() -> AppIconBadgeViewModel {
        AppIconBadgeViewModel(store: appIconBadgeCenter, permissionRequester: appIconBadgePermissionRequester)
    }

    /// The device-wide "Group Overdue Notifications" toggle on the Settings
    /// landing screen's "General" section — see
    /// `GroupOverdueNotificationsViewModel`'s doc comment for why this is a
    /// separate view model from `makeNotificationsViewModel`'s, not one more
    /// property on it.
    func makeGroupOverdueNotificationsViewModel() -> GroupOverdueNotificationsViewModel {
        GroupOverdueNotificationsViewModel(
            store: groupOverdueNotificationsStore,
            accountStore: accountStore,
            notificationSettingsStore: notificationSettingsStore,
            pushNotificationRegistering: pushNotificationRegistering,
        )
    }

    func makeDefaultProjectSettingsViewModel(account: InstanceAccount) -> DefaultProjectSettingsViewModel {
        let tokenProvider = tokenProvider(for: account)
        return DefaultProjectSettingsViewModel(
            userRepository: clientFactory.makeUserRepository(baseURL: account.baseURL, tokenProvider: tokenProvider),
            projectRepository: offlineProjectRepository(for: account),
            defaultProjectCache: AccountDefaultProjectCache(store: defaultProjectStore, accountID: account.id),
            timezoneCache: AccountTimezoneCache(store: accountTimezoneStore, accountID: account.id),
            displayNameCache: AccountDisplayNameCache(store: accountDisplayNameStore, accountID: account.id),
            toastPresenter: toastCenter,
        )
    }

    func makeHomeSelectionSettingsViewModel(account: InstanceAccount) -> HomeSelectionSettingsViewModel {
        HomeSelectionSettingsViewModel(
            projectRepository: offlineProjectRepository(for: account),
            store: AccountHomeSelectionCache(store: homeSelectionStore, accountID: account.id),
        )
    }

    func makeConnectionsListViewModel(onActiveAccountChanged: @escaping () -> Void) -> ConnectionsListViewModel {
        ConnectionsListViewModel(
            accountStore: accountStore,
            clientFactory: clientFactory,
            serverVersionCache: serverVersionStore,
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
            notificationSettingsStore: notificationSettingsStore,
            teardownNotifications: { [weak self] account in await self?.teardownNotifications(for: account) },
            toastPresenter: toastCenter,
            oidcAuthenticator: oidcAuthCoordinator,
            oidcRedirectURI: oidcRedirectURI,
            onActiveAccountChanged: onActiveAccountChanged,
        )
    }

    /// Deletes `account`'s webhooks and unregisters it from the push relay
    /// — called right before the account itself is removed
    /// (`ConnectionFormViewModel.deleteConnection()`), since the credential
    /// needed to delete the webhook server-side goes away with it. A no-op
    /// when notifications aren't enabled for this account. Best effort:
    /// every step is `try?` so a dead credential or an unreachable server
    /// never blocks removing the account — the webhook/relay registration
    /// are then orphaned, a known limitation (see the Notifications docs).
    func teardownNotifications(for account: InstanceAccount) async {
        guard notificationSettingsStore.settings(for: account.id).isEnabled else { return }

        let tokenProvider = tokenProvider(for: account)
        let userRepository = clientFactory.makeUserRepository(baseURL: account.baseURL, tokenProvider: tokenProvider)
        if let user = try? await userRepository.fetchCurrentUser(),
           let registration = try? await pushNotificationRegistering.enable(
               vikunjaUserID: user.id,
               accountID: account.id,
           ) {
            let projectRepository = clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            )
            let projects = await (try? projectRepository.fetchProjects()) ?? []
            let webhookRepository = clientFactory.makeWebhookRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider,
            )
            let coordinator = WebhookSyncCoordinator(webhookRepository: webhookRepository)
            try? await coordinator.sync(
                settings: NotificationSettings(),
                registration: registration,
                projects: projects,
            )
        }
        try? await pushNotificationRegistering.disable(accountID: account.id)
    }

    /// Streams the active account's queued project/task mutations for
    /// `MainTabView`'s per-row sync indicators. Backed by a GRDB
    /// `ValueObservation` in `LocalStore`, so it emits again whenever the
    /// queue changes (enqueue, successful drain, failure, conflict) and needs
    /// no polling. Cancelled when the consuming `.task` is.
    func pendingSyncStatusUpdates(
        account: InstanceAccount,
    ) async -> AsyncThrowingStream<[SyncItemKey: SyncItemStatus], Error> {
        await localStore.observePendingSyncStatuses(accountID: account.id)
    }

    func makeSearchViewModel(account: InstanceAccount) -> SearchViewModel {
        let tokenProvider = tokenProvider(for: account)
        return SearchViewModel(
            taskRepository: offlineTaskRepository(for: account),
            projectRepository: offlineProjectRepository(for: account),
            toastPresenter: toastCenter,
            hapticPresenter: hapticCenter,
        )
    }

    /// Builds the `tokenProvider` closure every `make*Repository` call takes
    /// — routes through `sessionRefresher` so a password account's JWT is
    /// refreshed transparently, and an API-token account passes through with
    /// no behavior change.
    private func tokenProvider(for account: InstanceAccount) -> @Sendable () async throws -> String? {
        let sessionRefresher = sessionRefresher
        return { try await sessionRefresher.validToken(for: account) }
    }

    /// `SyncEngine` pulls and drains every entity with offline support for
    /// an account in one pass, so both `offlineProjectRepository(for:)` and
    /// `offlineLabelRepository(for:)` need this to build its own copy of
    /// `SyncEngine` — `OfflineLabelRepository` also keeps its own second
    /// reference, for `addLabel`/`removeLabel`'s pass-through.
    private func networkLabelRepository(for account: InstanceAccount) -> LabelRepositoryProtocol {
        clientFactory.makeLabelRepository(baseURL: account.baseURL, tokenProvider: tokenProvider(for: account))
    }

    /// `SyncEngine` needs this to pull/drain tasks in the same pass, and
    /// `offlineTaskRepository(for:)` needs it to build its own copy of
    /// `SyncEngine` too (mirrors `networkLabelRepository(for:)`).
    private func networkTaskRepository(for account: InstanceAccount) -> TaskRepositoryProtocol {
        clientFactory.makeTaskRepository(baseURL: account.baseURL, tokenProvider: tokenProvider(for: account))
    }

    /// Same reasoning as `networkTaskRepository(for:)`, for relations —
    /// every `SyncEngine` needs one to pull/drain relations alongside tasks,
    /// and `offlineTaskRelationRepository(for:)` needs it for its own copy.
    private func networkTaskRelationRepository(for account: InstanceAccount) -> TaskRelationRepositoryProtocol {
        clientFactory.makeTaskRelationRepository(baseURL: account.baseURL, tokenProvider: tokenProvider(for: account))
    }

    /// Same reasoning as `networkTaskRelationRepository(for:)`, for comments
    /// — every `SyncEngine` needs one to drain comment mutations, and
    /// `offlineTaskCommentRepository(for:)` needs it for its own copy.
    private func networkTaskCommentRepository(for account: InstanceAccount) -> TaskCommentRepositoryProtocol {
        clientFactory.makeTaskCommentRepository(baseURL: account.baseURL, tokenProvider: tokenProvider(for: account))
    }

    /// The `ProjectRepositoryProtocol` every screen reads/writes through —
    /// local-first, queuing a mutation and opportunistically draining it
    /// right away if the network happens to already be up. `networkRepository`
    /// below is now only what this and `syncCoordinator` call to actually
    /// talk to the server; nothing else is handed it directly.
    private func offlineProjectRepository(for account: InstanceAccount) -> ProjectRepositoryProtocol {
        let networkRepository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: tokenProvider(for: account),
        )
        let syncEngine = SyncEngine(
            localStore: localStore,
            projectRepository: networkRepository,
            labelRepository: networkLabelRepository(for: account),
            taskRepository: networkTaskRepository(for: account),
            relationRepository: networkTaskRelationRepository(for: account),
            commentRepository: networkTaskCommentRepository(for: account),
            accountID: account.id,
        )
        return OfflineProjectRepository(
            localStore: localStore,
            accountID: account.id,
            syncEngine: syncEngine,
            reachability: reachabilityMonitor,
        )
    }

    /// The `LabelRepositoryProtocol` every screen reads/writes through — same
    /// shape as `offlineProjectRepository(for:)`, now including
    /// `addLabel`/`removeLabel` (task-label association), which drain
    /// through this same `syncEngine`'s task queue.
    private func offlineLabelRepository(for account: InstanceAccount) -> LabelRepositoryProtocol {
        let networkRepository = networkLabelRepository(for: account)
        let syncEngine = SyncEngine(
            localStore: localStore,
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider(for: account),
            ),
            labelRepository: networkRepository,
            taskRepository: networkTaskRepository(for: account),
            relationRepository: networkTaskRelationRepository(for: account),
            commentRepository: networkTaskCommentRepository(for: account),
            accountID: account.id,
        )
        return OfflineLabelRepository(
            localStore: localStore,
            accountID: account.id,
            syncEngine: syncEngine,
            reachability: reachabilityMonitor,
        )
    }

    /// The `TaskRepositoryProtocol` every screen reads/writes through for a
    /// task's core fields — same shape as `offlineProjectRepository(for:)`.
    /// Task sub-resources now offline too (labels, relations, comments) have
    /// their own dedicated repository (`offlineLabelRepository(for:)`,
    /// `offlineTaskRelationRepository(for:)`, `offlineTaskCommentRepository(for:)`);
    /// attachments still go straight to `VikunjaNetworking` and stay
    /// online-only by design.
    private func offlineTaskRepository(for account: InstanceAccount) -> TaskRepositoryProtocol {
        let syncEngine = SyncEngine(
            localStore: localStore,
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider(for: account),
            ),
            labelRepository: networkLabelRepository(for: account),
            taskRepository: networkTaskRepository(for: account),
            relationRepository: networkTaskRelationRepository(for: account),
            commentRepository: networkTaskCommentRepository(for: account),
            accountID: account.id,
        )
        return OfflineTaskRepository(
            localStore: localStore,
            accountID: account.id,
            syncEngine: syncEngine,
            reachability: reachabilityMonitor,
        )
    }

    /// The `TaskRelationRepositoryProtocol` every screen reads/writes
    /// through — same shape as `offlineLabelRepository(for:)`:
    /// `addRelation`/`removeRelation` drain through this same `syncEngine`'s
    /// task queue, resolved by `drainTaskRelationMutation`.
    private func offlineTaskRelationRepository(for account: InstanceAccount) -> TaskRelationRepositoryProtocol {
        let syncEngine = SyncEngine(
            localStore: localStore,
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider(for: account),
            ),
            labelRepository: networkLabelRepository(for: account),
            taskRepository: networkTaskRepository(for: account),
            relationRepository: networkTaskRelationRepository(for: account),
            commentRepository: networkTaskCommentRepository(for: account),
            accountID: account.id,
        )
        return OfflineTaskRelationRepository(
            localStore: localStore,
            accountID: account.id,
            syncEngine: syncEngine,
            reachability: reachabilityMonitor,
        )
    }

    /// The `TaskCommentRepositoryProtocol` every screen reads/writes through
    /// — same shape as `offlineTaskRelationRepository(for:)`. Comments are
    /// queued as their own `.comment` mutations (not against the task row),
    /// because a comment has its own server id even though it can't sync
    /// before its task does.
    private func offlineTaskCommentRepository(for account: InstanceAccount) -> TaskCommentRepositoryProtocol {
        let networkRepository = networkTaskCommentRepository(for: account)
        let syncEngine = SyncEngine(
            localStore: localStore,
            projectRepository: clientFactory.makeProjectRepository(
                baseURL: account.baseURL,
                tokenProvider: tokenProvider(for: account),
            ),
            labelRepository: networkLabelRepository(for: account),
            taskRepository: networkTaskRepository(for: account),
            relationRepository: networkTaskRelationRepository(for: account),
            commentRepository: networkRepository,
            accountID: account.id,
        )
        return OfflineTaskCommentRepository(
            localStore: localStore,
            accountID: account.id,
            syncEngine: syncEngine,
            reachability: reachabilityMonitor,
            currentUser: currentUserStore.user(for: account.id),
        )
    }
}
