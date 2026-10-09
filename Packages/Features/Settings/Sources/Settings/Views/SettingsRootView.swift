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
    private let onPreviewOnboarding: () -> Void
    private let makeConnectionsListViewModel: () -> ConnectionsListViewModel
    private let makeConnectionFormViewModel: (ConnectionFormMode) -> ConnectionFormViewModel
    private let makeManageLabelsViewModel: () -> ManageLabelsViewModel
    private let makeNotificationsViewModel: () -> NotificationsViewModel

    /// `router` is owned by the app target's `MainTabView`, alongside its
    /// other tab routers, so it can push a reconnect screen onto this stack
    /// itself. `account` is the currently active connection — shown on the
    /// landing screen's "Connections" row. `themeStore` backs the
    /// "Appearance" row. `isDevBuild`/`devBadgeStore`/`networkLoggingStore`/
    /// `onPreviewOnboarding` back the Developer section, shown only in dev
    /// builds (see `BuildConfig.isDevBuild` in the app target).
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
        onPreviewOnboarding: @escaping () -> Void,
        makeConnectionsListViewModel: @escaping () -> ConnectionsListViewModel,
        makeConnectionFormViewModel: @escaping (ConnectionFormMode) -> ConnectionFormViewModel,
        makeManageLabelsViewModel: @escaping () -> ManageLabelsViewModel,
        makeNotificationsViewModel: @escaping () -> NotificationsViewModel,
    ) {
        self.router = router
        self.account = account
        self.themeStore = themeStore
        self.quickAddSyntaxStore = quickAddSyntaxStore
        self.isDevBuild = isDevBuild
        self.devBadgeStore = devBadgeStore
        self.networkLoggingStore = networkLoggingStore
        self.onPreviewOnboarding = onPreviewOnboarding
        self.makeConnectionsListViewModel = makeConnectionsListViewModel
        self.makeConnectionFormViewModel = makeConnectionFormViewModel
        self.makeManageLabelsViewModel = makeManageLabelsViewModel
        self.makeNotificationsViewModel = makeNotificationsViewModel
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
                themeStore: themeStore,
                quickAddSyntaxStore: quickAddSyntaxStore,
                isDevBuild: isDevBuild,
                devBadgeStore: devBadgeStore,
                networkLoggingStore: networkLoggingStore,
                onPreviewOnboarding: onPreviewOnboarding,
                router: router,
            )
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .connections:
                    ConnectionsListView(makeViewModel: makeConnectionsListViewModel, router: router)
                case let .connectionForm(mode):
                    ConnectionFormView(makeViewModel: { makeConnectionFormViewModel(mode) }, router: router)
                case .manageLabels:
                    ManageLabelsView(makeViewModel: makeManageLabelsViewModel)
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
