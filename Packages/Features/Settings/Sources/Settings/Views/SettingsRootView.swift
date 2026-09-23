import SwiftUI
import VikuNavigation
import VikunjaCore

/// Settings' entry point for the app target: owns the tab's own
/// `NavigationStack` and `Router<SettingsRoute>`, so pushing a screen from
/// inside Settings never needs the app target or another feature to know
/// about it.
public struct SettingsRootView: View {
    @State private var router = Router<SettingsRoute>()
    private let account: InstanceAccount
    private let themeStore: AppThemeStoring
    private let isDevBuild: Bool
    private let devBadgeStore: DevBadgeVisibilityStoring
    private let networkLoggingStore: NetworkRequestLoggingStoring
    private let onPreviewOnboarding: () -> Void
    private let makeConnectionsListViewModel: () -> ConnectionsListViewModel
    private let makeConnectionFormViewModel: (ConnectionFormMode) -> ConnectionFormViewModel
    private let makeManageLabelsViewModel: () -> ManageLabelsViewModel

    /// `account` is the currently active connection — shown on the landing
    /// screen's "Connections" row. `themeStore` backs the "Appearance" row.
    /// `isDevBuild`/`devBadgeStore`/`networkLoggingStore`/
    /// `onPreviewOnboarding` back the Developer section, shown only in dev
    /// builds (see `BuildConfig.isDevBuild` in the app target).
    /// `makeConnectionsListViewModel`/`makeConnectionFormViewModel`
    /// come from the app target's `AppContainer`, the only place allowed to
    /// know about the concrete `AccountStoreProtocol`/
    /// `InstanceClientFactoryProtocol` these view models need.
    public init(
        account: InstanceAccount,
        themeStore: AppThemeStoring,
        isDevBuild: Bool,
        devBadgeStore: DevBadgeVisibilityStoring,
        networkLoggingStore: NetworkRequestLoggingStoring,
        onPreviewOnboarding: @escaping () -> Void,
        makeConnectionsListViewModel: @escaping () -> ConnectionsListViewModel,
        makeConnectionFormViewModel: @escaping (ConnectionFormMode) -> ConnectionFormViewModel,
        makeManageLabelsViewModel: @escaping () -> ManageLabelsViewModel,
    ) {
        self.account = account
        self.themeStore = themeStore
        self.isDevBuild = isDevBuild
        self.devBadgeStore = devBadgeStore
        self.networkLoggingStore = networkLoggingStore
        self.onPreviewOnboarding = onPreviewOnboarding
        self.makeConnectionsListViewModel = makeConnectionsListViewModel
        self.makeConnectionFormViewModel = makeConnectionFormViewModel
        self.makeManageLabelsViewModel = makeManageLabelsViewModel
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            SettingsView(
                activeAccountName: account.displayName,
                themeStore: themeStore,
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
                case .about:
                    AboutView()
                }
            }
        }
    }
}
