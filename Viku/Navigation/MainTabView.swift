import CalendarFeature
import Home
import Projects
import Search
import Settings
import SwiftUI
import Tasks
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

/// The app's main navigation shell once a connection exists: a floating,
/// Liquid Glass tab bar (the default look for `TabView` on iOS 26+) with one
/// independent `NavigationStack` per tab, each owned by its own feature
/// module. `Search` uses iOS 26's dedicated `.search` tab role, which renders
/// it as a separated glass pill instead of grouping it with the others. The
/// quick-add button is a plain `.overlay`, not `.tabViewBottomAccessory` —
/// that API always paints a system glass background behind its content and
/// centers it over the tab bar, which can't be suppressed or anchored to a
/// corner, so it can't match the mockup's bare floating FAB.
struct MainTabView: View {
    let account: InstanceAccount
    let container: AppContainer
    /// Called after `Settings`' connection screens make a change that may
    /// have altered which account is active (switching, deleting the active
    /// one, or editing its own address) — `RootView` re-reads the active
    /// account and, since it renders this view keyed by `.id(connectedAccount)`,
    /// a changed value tears this whole tab shell down and rebuilds it against
    /// the new one. Dropping the last connection surfaces here too: the
    /// re-read comes back `nil` and `RootView` falls back to onboarding.
    let onAccountsChanged: () -> Void

    @State private var selection: AppTab = .home

    // One `AppRouter` per tab stack: the tab's `NavigationStack` binds to its
    // `path` and it's placed in that stack's environment, so any screen inside
    // - across feature module boundaries - navigates by pushing an `AppRoute`.
    // Held in `@State` (stable across `body` re-evaluation, like the view
    // models below) and rebuilt on account switch via `.id(connectedAccount)`.
    @State private var homeRouter = AppRouter()
    @State private var projectsRouter = AppRouter()
    @State private var calendarRouter = AppRouter()
    @State private var searchRouter = AppRouter()

    // Each tab's root view model is built once, here, and held for the life of
    // this shell (which is itself keyed `.id(connectedAccount)`, so switching
    // account still rebuilds them). Building them inside `body` instead meant a
    // fresh, empty view model on every `body` re-evaluation — and `body` re-runs
    // on every tab switch as soon as anything reads `selection` (the haptic
    // tick) — which flashed a loading spinner on the tab being switched to.
    @State private var todayViewModel: TodayViewModel
    @State private var projectsViewModel: ProjectsListViewModel
    @State private var calendarViewModel: CalendarViewModel
    @State private var searchViewModel: SearchViewModel

    init(account: InstanceAccount, container: AppContainer, onAccountsChanged: @escaping () -> Void) {
        self.account = account
        self.container = container
        self.onAccountsChanged = onAccountsChanged
        _todayViewModel = State(initialValue: container.makeTodayViewModel(account: account))
        _projectsViewModel = State(initialValue: container.makeProjectsListViewModel(account: account))
        _calendarViewModel = State(initialValue: container.makeCalendarViewModel(account: account))
        _searchViewModel = State(initialValue: container.makeSearchViewModel(account: account))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: .home) {
                NavigationStack(path: $homeRouter.path) {
                    HomeRootView(viewModel: todayViewModel)
                        .appDestinations(container: container, account: account)
                }
                .environment(homeRouter)
            }

            Tab(AppTab.projects.title, systemImage: AppTab.projects.systemImage, value: .projects) {
                NavigationStack(path: $projectsRouter.path) {
                    ProjectsRootView(
                        viewModel: projectsViewModel,
                        makeOverviewViewModel: { node in
                            container.makeProjectOverviewViewModel(node: node, account: account)
                        },
                        makeCreateProjectViewModel: {
                            container.makeCreateProjectViewModel(account: account)
                        },
                        makeEditProjectViewModel: { project in
                            container.makeEditProjectViewModel(project: project, account: account)
                        },
                    )
                    .appDestinations(container: container, account: account)
                }
                .environment(projectsRouter)
            }

            Tab(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage, value: .calendar) {
                NavigationStack(path: $calendarRouter.path) {
                    CalendarRootView(viewModel: calendarViewModel)
                        .appDestinations(container: container, account: account)
                }
                .environment(calendarRouter)
            }

            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: .settings) {
                SettingsRootView(
                    account: account,
                    themeStore: container.themeCenter,
                    makeConnectionsListViewModel: {
                        container.makeConnectionsListViewModel(onActiveAccountChanged: onAccountsChanged)
                    },
                    makeConnectionFormViewModel: { mode in
                        container.makeConnectionFormViewModel(mode: mode, onActiveAccountChanged: onAccountsChanged)
                    },
                    makeManageLabelsViewModel: {
                        container.makeManageLabelsViewModel(account: account)
                    },
                )
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchRouter.path) {
                    SearchRootView(viewModel: searchViewModel)
                        .appDestinations(container: container, account: account)
                }
                .environment(searchRouter)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(VikuColor.brandPrimary)
        // A light selection tick whenever the active tab changes — including a
        // programmatic switch from a `viku://` deep link. Doesn't fire on
        // first render, or on re-tapping the current tab (which pops to root
        // rather than changing `selection`). Reading `selection` here (like the
        // old `.vikuHaptic(trigger:)`) makes `body` re-run on every tab
        // switch; that's only cheap because the tab view models are now held in
        // `@State` rather than rebuilt inside `body`.
        .onChange(of: selection) { _, _ in
            container.hapticCenter.play(.selection)
        }
        .overlay(alignment: .topTrailing) {
            if BuildConfig.isDevBuild {
                Text("DEV")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.orange, in: Circle())
                    .padding(VikuSpacing.md)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            QuickAddOverlay(container: container, account: account)
                .padding(.trailing, VikuSpacing.md)
                .padding(.bottom, VikuSpacing.xxl + VikuSpacing.lg)
        }
    }
}

/// The floating quick-add button and its sheet, split out of `MainTabView` so
/// that opening/closing the sheet — and snapshotting the quick-add project
/// context on tap — only re-evaluates this small view, never `MainTabView`'s
/// body. Left in `MainTabView`, that `@State` toggle rebuilt every tab's
/// `NavigationStack` and its view models on each open, blanking whatever
/// screen was behind the sheet.
private struct QuickAddOverlay: View {
    let container: AppContainer
    let account: InstanceAccount

    @State private var isShowingSheet = false
    /// Snapshot of `container.quickAddContext.preselectedProjectID` taken in
    /// the tap handler (not in `body`) so reading the `@Observable` context
    /// doesn't rebuild the sheet's view model whenever a project screen's
    /// scope enters or leaves the stack.
    @State private var preselectedProjectID: Int?

    var body: some View {
        QuickAddButton {
            preselectedProjectID = container.quickAddContext.preselectedProjectID
            isShowingSheet = true
        }
        .sheet(isPresented: $isShowingSheet) {
            QuickAddSheetView(
                viewModel: container.makeQuickAddTaskViewModel(
                    preselectedProjectID: preselectedProjectID,
                    account: account,
                ),
            )
        }
        // A `viku://quick-add` deep link opens the same sheet. Handled
        // here, not in `MainTabView`, so reading the router doesn't rebuild
        // every tab's `NavigationStack`. `.onChange` covers a link that
        // arrives while the shell is up; `.task` covers one already parked
        // on the router when this overlay mounts (cold launch).
        .onChange(of: container.deepLinkRouter.pending) { _, link in
            handleDeepLink(link)
        }
        .task {
            handleDeepLink(container.deepLinkRouter.pending)
        }
    }

    private func handleDeepLink(_ link: DeepLink?) {
        guard case let .quickAdd(projectID) = link else { return }
        preselectedProjectID = projectID ?? container.quickAddContext.preselectedProjectID
        isShowingSheet = true
        container.deepLinkRouter.clear()
    }
}
