import Onboarding
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

/// Top-level navigation between Features. Features never reference each other
/// directly, so switching from Onboarding to the main tab bar happens only
/// here, in the composition root. Also where the app's single toast host is
/// attached, so a toast floats above every screen — onboarding, tabs, and
/// sheets alike — regardless of which one triggered it.
struct RootView: View {
    let container: AppContainer

    @State private var connectedAccount: InstanceAccount?
    @State private var hasCheckedForSavedAccount = false
    /// Drives the dev-only "Preview Onboarding" row in Settings — see
    /// `OnboardingPreviewView`. Session-only `@State`, not persisted.
    @State private var isPreviewingOnboarding = false

    var body: some View {
        Group {
            if let connectedAccount {
                // Keyed by the whole `InstanceAccount` value (not just its
                // id) so switching the active connection, or editing the
                // active one's own name/URL, tears down and rebuilds the
                // entire tab shell — every tab's view models were built
                // against the old account's `baseURL` at construction time
                // and don't observe changes to it.
                MainTabView(
                    account: connectedAccount,
                    container: container,
                    onAccountsChanged: { Task { await refreshActiveAccount() } },
                    onPreviewOnboarding: { isPreviewingOnboarding = true },
                )
                .id(connectedAccount)
            } else if hasCheckedForSavedAccount {
                NavigationStack {
                    InstanceSetupView(
                        makeViewModel: container.makeInstanceSetupViewModel,
                        onConnectionSaved: { account in
                            connectedAccount = account
                            Task { await container.refreshDefaultProject(account: account) }
                        },
                    )
                }
            } else {
                ProgressView()
            }
        }
        .task {
            // Move any pre-existing Keychain items into the shared access
            // group before the first read, so a returning user keeps their
            // account (and the widget can see it).
            await container.bootstrap()
            // The Keychain lookup is async, so without this the app would
            // always render onboarding first — even with a saved account —
            // until this resolves.
            await refreshActiveAccount()
            hasCheckedForSavedAccount = true
            // Seed the widgets' shared snapshots on launch, so the Today and
            // Calendar widgets have data even before the app is next
            // backgrounded.
            if connectedAccount != nil {
                Task { await container.refreshWidgetSnapshots() }
            }
        }
        .onOpenURL { url in
            // Parked on the router until the screen that acts on it is
            // mounted — on a cold launch this fires before the tab shell
            // exists. See `DeepLinkRouter`.
            guard let link = DeepLink(url: url) else { return }
            container.deepLinkRouter.open(link)
        }
        .toastHost(container.toastCenter)
        // Applied at the root so every screen — onboarding, tabs, sheets —
        // follows the user's theme preference. `nil` (the `.system` case)
        // leaves the view hierarchy following the device setting.
        .preferredColorScheme(container.themeCenter.colorScheme)
        // Dev-only: lets a saved-in user look at the first-launch screen
        // again without deleting their real connection. Saving a connection
        // here still goes through the normal flow and switches the active
        // account, exactly like real onboarding would.
        .fullScreenCover(isPresented: $isPreviewingOnboarding) {
            OnboardingPreviewView(
                container: container,
                onConnectionSaved: { account in
                    connectedAccount = account
                    isPreviewingOnboarding = false
                    Task { await container.refreshDefaultProject(account: account) }
                },
                onClose: { isPreviewingOnboarding = false },
            )
        }
    }

    /// Re-reads the active account from the store and updates
    /// `connectedAccount` accordingly — `nil` drops back to onboarding (e.g.
    /// the last connection was just deleted). `Settings`' view models fire
    /// their "active account changed" callback synchronously, so
    /// `MainTabView.onAccountsChanged` wraps this in its own `Task`.
    private func refreshActiveAccount() async {
        connectedAccount = try? await container.accountStore.activeAccount()
        // Refresh the cached default project once per launch and on every
        // account switch — quick-add reads the cache, never the network.
        if let connectedAccount {
            Task { await container.refreshDefaultProject(account: connectedAccount) }
        }
    }
}
