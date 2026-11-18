import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
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
        PasswordSessionRefresher(accountStore: makeAccountStore(), cancelRefreshOnCancellation: true)
    }

    private static func reloadTaskTimelines() async {
        #if canImport(WidgetKit)
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: VikuWidgetConfig.todayWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: VikuWidgetConfig.calendarWidgetKind)
        }
        #endif
    }

    private static let coordinator: SyncCoordinator? = {
        guard let sharedLocalStore else { return nil }
        let refresher = makeSessionRefresher()
        return SyncCoordinator(
            localStore: sharedLocalStore,
            accountStore: makeAccountStore(),
            clientFactory: VikunjaInstanceClientFactory(),
            reachability: NWPathReachabilityMonitor(),
            tokenProvider: { account in { try await refresher.validToken(for: account) } },
            onAccountDataChanged: {
                await reloadTaskTimelines()
            },
        )
    }()

    public static func synchronize(accountID: UUID, taskID: EntityID? = nil) async throws {
        guard let coordinator else { throw LocalStoreError.containerUnavailable }
        try await WidgetSynchronization.run {
            try await coordinator.refresh(
                accountID: accountID, scope: taskID.map(SyncScope.taskUpload) ?? .account,
                cancelWorkerOnCancellation: true,
            )
        }
    }

    public static func makeSnapshotLoader() -> TodaySnapshotLoader {
        TodaySnapshotLoader(
            accountStore: makeAccountStore(),
            localSnapshotProvider: makeLocalSnapshotProvider(),
            synchronize: { try await synchronize(accountID: $0) },
        )
    }

    public static func makeCalendarSnapshotLoader() -> CalendarSnapshotLoader {
        CalendarSnapshotLoader(
            accountStore: makeAccountStore(),
            localSnapshotProvider: makeLocalSnapshotProvider(),
            synchronize: { try await synchronize(accountID: $0) },
        )
    }

    public static func makeCompletion(
        accountID: UUID, taskID: Int,
    ) async throws -> WidgetTaskCompletion {
        guard let sharedLocalStore else { throw LocalStoreError.containerUnavailable }
        // Bind to the timeline's connection, never a newly active account that
        // might happen to have the same server-local task ID.
        guard try await makeAccountStore().fetchAccounts().contains(where: { $0.id == accountID }) else {
            throw VikunjaError.notFound
        }
        let repository = OfflineTaskRepository(
            localStore: sharedLocalStore, accountID: accountID, syncRequester: WidgetSyncRequester(),
        )
        return WidgetTaskCompletion(
            repository: repository,
            synchronize: { try await synchronize(accountID: accountID, taskID: .remote(taskID)) },
            reload: {
                await reloadTaskTimelines()
            },
        )
    }
}

/// The intent explicitly awaits a bounded sync after publishing local acceptance.
private struct WidgetSyncRequester: SyncRequesting {
    func requestSync() async {}
}

private struct UnavailableLocalTaskSnapshotProvider: WidgetLocalTaskSnapshotProviding {
    func loadSnapshot(accountID _: UUID?) async -> LocalTaskSnapshot? {
        nil
    }
}
