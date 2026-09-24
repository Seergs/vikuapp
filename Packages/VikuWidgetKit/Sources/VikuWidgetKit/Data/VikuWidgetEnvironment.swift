import Foundation
import VikuAuth
import VikunjaCore
import VikunjaNetworking

/// Builds the concrete `VikuAuth`/`VikunjaNetworking` types the widget
/// runs against — the widget's equivalent of the app target's `AppContainer`.
/// The extension is not a `Features/*` module, so importing the networking and
/// auth layers here is allowed.
public enum VikuWidgetEnvironment {
    public static func makeAccountStore() -> KeychainAccountStore {
        KeychainAccountStore(
            service: VikuWidgetConfig.accountStoreService,
            accessGroup: VikuWidgetConfig.keychainAccessGroup,
        )
    }

    public static func makeSnapshotCache() -> TodaySnapshotCache {
        TodaySnapshotCache(appGroupIdentifier: VikuWidgetConfig.appGroupIdentifier)
    }

    public static func makeCalendarSnapshotCache() -> CalendarSnapshotCache {
        CalendarSnapshotCache(appGroupIdentifier: VikuWidgetConfig.appGroupIdentifier)
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
            cache: makeSnapshotCache(),
            tokenResolver: { try await sessionRefresher.validToken(for: $0) },
        )
    }

    public static func makeCalendarSnapshotLoader() -> CalendarSnapshotLoader {
        let sessionRefresher = makeSessionRefresher()
        return CalendarSnapshotLoader(
            accountStore: makeAccountStore(),
            clientFactory: VikunjaInstanceClientFactory(),
            cache: makeCalendarSnapshotCache(),
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
