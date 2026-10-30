import SwiftUI
import VikuNavigation
import VikunjaCore

/// Settings' entry point for the app target: hosts the tab's own
/// `NavigationStack` around a `Router<SettingsRoute>`, so pushing a screen
/// from inside Settings never needs another feature to know about it.
///
/// Unlike the other tabs, `router` is passed in rather than owned here
/// (`@State` in `MainTabView`, alongside `homeRouter`/`projectsRouter`/etc.)
/// — `MainTabView` needs to be able to push onto it itself, to jump straight
/// to the reconnect screen when a session expires while the user is on a
/// different tab.
public struct SettingsRootView: View {
    private let router: Router<SettingsRoute>
    private let account: InstanceAccount
    private let themeStore: AppThemeStoring
    private let quickAddSyntaxStore: QuickAddSyntaxStore
    private let isDevBuild: Bool
    private let devBadgeStore: DevBadgeVisibilityStoring
    private let networkLoggingStore: NetworkRequestLoggingStoring
    private let whatsNewSeenVersionStore: WhatsNewSeenVersionStoring
    private let onPreviewOnboarding: () -> Void
    private let makeConnectionsListViewModel: () -> ConnectionsListViewModel
    private let makeConnectionFormViewModel: (ConnectionFormMode) -> ConnectionFormViewModel
    private let makeManageLabelsViewModel: () -> ManageLabelsViewModel
    private let makePendingSyncViewModel: () -> PendingSyncViewModel
    private let makeNotificationsViewModel: () -> NotificationsViewModel
    @State private var pendingSyncViewModel: PendingSyncViewModel
    /// Built once in `init`, not lazily like `notificationsViewModelCache` —
    /// unlike Notifications, the badge toggle lives directly on this
    /// landing screen, so its view model needs to exist from the start.
    @State private var badgeViewModel: AppIconBadgeViewModel
    /// Same reasoning as `badgeViewModel`: the "Group Overdue Notifications"
    /// toggle also lives directly on this landing screen (see
    /// `GroupOverdueNotificationsViewModel`'s doc comment for why it's not
    /// folded into `notificationsViewModelCache` instead).
    @State private var groupOverdueNotificationsViewModel: GroupOverdueNotificationsViewModel
    /// Same reasoning as `badgeViewModel`: the "Default Project" row lives
    /// directly on this landing screen, so its view model needs to exist
    /// from the start rather than being built lazily on first visit.
    @State private var defaultProjectViewModel: DefaultProjectSettingsViewModel
    /// Same reasoning as `defaultProjectViewModel`: the "Home Screen" row
    /// lives directly on this landing screen too.
    @State private var homeSelectionViewModel: HomeSelectionSettingsViewModel

    /// `router` is owned by the app target's `MainTabView`, alongside its
    /// other tab routers, so it can push a reconnect screen onto this stack
    /// itself. `account` is the currently active connection — shown on the
    /// landing screen's "Connections" row. `themeStore` backs the
    /// "Appearance" row. `isDevBuild`/`devBadgeStore`/`networkLoggingStore`/
    /// `whatsNewSeenVersionStore`/`onPreviewOnboarding` back the Developer
    /// section, shown only in dev builds (see `BuildConfig.isDevBuild` in
    /// the app target).
    /// `makeConnectionsListViewModel`/`makeConnectionFormViewModel`
    /// come from the app target's `AppContainer`, the only place allowed to
    /// know about the concrete `AccountStoreProtocol`/
    /// `InstanceClientFactoryProtocol` these view models need.
    public init(
        router: Router<SettingsRoute>,
        account: InstanceAccount,
        themeStore: AppThemeStoring,
        quickAddSyntaxStore: QuickAddSyntaxStore,
        isDevBuild: Bool,
        devBadgeStore: DevBadgeVisibilityStoring,
        networkLoggingStore: NetworkRequestLoggingStoring,
        whatsNewSeenVersionStore: WhatsNewSeenVersionStoring,
        onPreviewOnboarding: @escaping () -> Void,
        makeConnectionsListViewModel: @escaping () -> ConnectionsListViewModel,
        makeConnectionFormViewModel: @escaping (ConnectionFormMode) -> ConnectionFormViewModel,
        makeManageLabelsViewModel: @escaping () -> ManageLabelsViewModel,
        makePendingSyncViewModel: @escaping () -> PendingSyncViewModel,
        makeNotificationsViewModel: @escaping () -> NotificationsViewModel,
        makeAppIconBadgeViewModel: @escaping () -> AppIconBadgeViewModel,
        makeGroupOverdueNotificationsViewModel: @escaping () -> GroupOverdueNotificationsViewModel,
        makeDefaultProjectSettingsViewModel: @escaping () -> DefaultProjectSettingsViewModel,
        makeHomeSelectionSettingsViewModel: @escaping () -> HomeSelectionSettingsViewModel,
    ) {
        self.router = router
        self.account = account
        self.themeStore = themeStore
        self.quickAddSyntaxStore = quickAddSyntaxStore
        self.isDevBuild = isDevBuild
        self.devBadgeStore = devBadgeStore
        self.networkLoggingStore = networkLoggingStore
        self.whatsNewSeenVersionStore = whatsNewSeenVersionStore
        self.onPreviewOnboarding = onPreviewOnboarding
        self.makeConnectionsListViewModel = makeConnectionsListViewModel
        self.makeConnectionFormViewModel = makeConnectionFormViewModel
        self.makeManageLabelsViewModel = makeManageLabelsViewModel
        self.makePendingSyncViewModel = makePendingSyncViewModel
        self.makeNotificationsViewModel = makeNotificationsViewModel
        self._pendingSyncViewModel = State(initialValue: makePendingSyncViewModel())
        self._badgeViewModel = State(initialValue: makeAppIconBadgeViewModel())
        self._groupOverdueNotificationsViewModel = State(initialValue: makeGroupOverdueNotificationsViewModel())
        self._defaultProjectViewModel = State(initialValue: makeDefaultProjectSettingsViewModel())
        self._homeSelectionViewModel = State(initialValue: makeHomeSelectionSettingsViewModel())
    }

    /// Holds the one `NotificationsViewModel` instance for this screen's
    /// lifetime, built lazily on first visit to `.notifications` — plain
    /// reference-type storage (not `@State`) so filling it while building a
    /// `.projectNotifications` destination never mutates SwiftUI state
    /// mid-render. `.notifications` and `.projectNotifications(_:)` both
    /// read/write the same `settings`, so they need the same instance:
    /// unlike `ConnectionFormView`/`ManageLabelsView`, which each get a fresh
    /// view model from their factory per push, these two must share state
    /// without a reload. Mirrors `ProjectsRootView.overviewViewModelCache`.
    @State private var notificationsViewModelCache = NotificationsViewModelCache()

    public var body: some View {
        // `router` is a reference type owned outside this view (unlike the
        // other tab roots, which get an `@State`-owned router and can use
        // its `$`-projected binding directly) — this builds the same
        // read/write binding by hand so `MainTabView` can still push onto
        // the identical `NavigationPath` instance.
        NavigationStack(path: Binding(get: { router.path }, set: { router.path = $0 })) {
            SettingsView(
                activeAccountName: account.displayName,
                activeAccountHost: account.displayHost,
                themeStore: themeStore,
                quickAddSyntaxStore: quickAddSyntaxStore,
                badgeViewModel: badgeViewModel,
                pendingSyncViewModel: pendingSyncViewModel,
                groupOverdueNotificationsViewModel: groupOverdueNotificationsViewModel,
                defaultProjectViewModel: defaultProjectViewModel,
                homeSelectionViewModel: homeSelectionViewModel,
                isDevBuild: isDevBuild,
                devBadgeStore: devBadgeStore,
                networkLoggingStore: networkLoggingStore,
                whatsNewSeenVersionStore: whatsNewSeenVersionStore,
                onPreviewOnboarding: onPreviewOnboarding,
                router: router,
            )
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appearance:
                    AppearancePickerView(themeStore: themeStore)
                case .connections:
                    ConnectionsListView(makeViewModel: makeConnectionsListViewModel, router: router)
                case let .connectionForm(mode):
                    ConnectionFormView(makeViewModel: { makeConnectionFormViewModel(mode) }, router: router)
                case .manageLabels:
                    ManageLabelsView(makeViewModel: makeManageLabelsViewModel)
                case .pendingSync:
                    PendingSyncView(makeViewModel: makePendingSyncViewModel)
                case .notifications:
                    NotificationsView(viewModel: cachedNotificationsViewModel(), router: router)
                case let .projectNotifications(project):
                    ProjectNotificationsView(viewModel: cachedNotificationsViewModel(), project: project)
                case .about:
                    AboutView()
                }
            }
        }
    }

    /// Returns the cached `NotificationsViewModel`, creating and storing one
    /// on first visit — see `notificationsViewModelCache`'s doc comment.
    private func cachedNotificationsViewModel() -> NotificationsViewModel {
        if let existing = notificationsViewModelCache.instance {
            return existing
        }
        let viewModel = makeNotificationsViewModel()
        notificationsViewModelCache.instance = viewModel
        return viewModel
    }
}

/// Backs `SettingsRootView.notificationsViewModelCache` — a class rather
/// than a struct so `@State` only needs to preserve *its identity*, mirrors
/// `ProjectsRootView.OverviewViewModelCache`.
@MainActor
private final class NotificationsViewModelCache {
    var instance: NotificationsViewModel?
}
