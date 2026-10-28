import Foundation
import VikuAuth
import VikunjaCore
import VikunjaNetworking
import VikunjaPersistence

/// Builds the concrete `VikuAuth`/`VikunjaNetworking`/`VikunjaPersistence`
/// types the widget runs against — the widget's equivalent of the app target's
/// `AppContainer`. The extension is not a `Features/*` module, so importing the
/// networking, auth, and persistence layers here is allowed.
public enum VikuWidgetEnvironment {
    private static let sharedLocalStore = try? LocalStore(
        appGroupIdentifier: VikuWidgetConfig.appGroupIdentifier,
    )

    public static func makeAccountStore() -> KeychainAccountStore {
        KeychainAccountStore(
            service: VikuWidgetConfig.accountStoreService,
            accessGroup: VikuWidgetConfig.keychainAccessGroup,
        )
    }

    /// Reads the app's shared offline database without touching the network.
    /// Returns a no-op provider when the App Group container is unavailable.
    public static func makeLocalSnapshotProvider() -> any WidgetLocalTaskSnapshotProviding {
        guard let sharedLocalStore else {
            return UnavailableLocalTaskSnapshotProvider()
        }
        return LocalStoreWidgetSnapshotProvider(localStore: sharedLocalStore)
    }

    /// Refreshes a password account's JWT before it expires — shared by both
    /// snapshot loaders and the toggle-done `AppIntent` below so a refresh
    /// triggered by one isn't immediately redone by the other.
    public static func makeSessionRefresher() -> PasswordSessionRefresher {
        PasswordSessionRefresher(accountStore: makeAccountStore())
    }

    public static func makeSnapshotLoader() -> TodaySnapshotLoader {
        let sessionRefresher = makeSessionRefresher()
        return TodaySnapshotLoader(
            accountStore: makeAccountStore(),
            clientFactory: VikunjaInstanceClientFactory(),
            localSnapshotProvider: makeLocalSnapshotProvider(),
            tokenResolver: { try await sessionRefresher.validToken(for: $0) },
        )
    }

    public static func makeCalendarSnapshotLoader() -> CalendarSnapshotLoader {
        let sessionRefresher = makeSessionRefresher()
        return CalendarSnapshotLoader(
            accountStore: makeAccountStore(),
            clientFactory: VikunjaInstanceClientFactory(),
            localSnapshotProvider: makeLocalSnapshotProvider(),
            tokenResolver: { try await sessionRefresher.validToken(for: $0) },
        )
    }

    /// The active account plus its token, for the toggle-done `AppIntent`.
    public static func makeTaskRepository() async -> TaskRepositoryProtocol? {
        let store = makeAccountStore()
        guard let account = try? await store.activeAccount() else { return nil }
        let token = try? await makeSessionRefresher().validToken(for: account)
        guard let token, !token.isEmpty else { return nil }

        return VikunjaInstanceClientFactory().makeTaskRepository(baseURL: account.baseURL) { token }
    }
}

private struct UnavailableLocalTaskSnapshotProvider: WidgetLocalTaskSnapshotProviding {
    func loadSnapshot(accountID _: UUID?) async -> LocalTaskSnapshot? {
        nil
    }
}
