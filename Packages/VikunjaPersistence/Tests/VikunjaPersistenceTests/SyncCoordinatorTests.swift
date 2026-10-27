import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor FakeAccountStore: AccountStoreProtocol {
    var accounts: [InstanceAccount] = []
    private var tokensByAccountID: [InstanceAccount.ID: String] = [:]

    func fetchAccounts() async throws -> [InstanceAccount] {
        accounts
    }

    func activeAccount() async throws -> InstanceAccount? {
        accounts.first
    }

    func addAccount(_ account: InstanceAccount, token: String) async throws {
        accounts.append(account)
        tokensByAccountID[account.id] = token
    }

    func updateAccount(_ account: InstanceAccount, token: String?) async throws {}

    func removeAccount(id: InstanceAccount.ID) async throws {
        accounts.removeAll { $0.id == id }
    }

    func setActiveAccount(id: InstanceAccount.ID) async throws {}

    func token(forAccountID id: InstanceAccount.ID) async throws -> String? {
        tokensByAccountID[id]
    }
}

/// Hands out one `FakeProjectRepository` per `baseURL`, so a test can look
/// up the exact fake a given account's `baseURL` resolved to and inspect
/// what `SyncCoordinator` did with it. Every other `make*Repository` is
/// unused by these tests.
private final class FakeInstanceClientFactory: InstanceClientFactoryProtocol, @unchecked Sendable {
    private var repositoriesByBaseURL: [URL: FakeProjectRepository] = [:]
    /// Captured, not invoked — lets a test check which `tokenProvider`
    /// `SyncCoordinator` actually threaded through for a given account's
    /// `baseURL`, by awaiting it directly.
    private(set) var tokenProvidersByBaseURL: [URL: @Sendable () async throws -> String?] = [:]

    func projectRepository(for baseURL: URL) -> FakeProjectRepository {
        if let existing = repositoriesByBaseURL[baseURL] {
            return existing
        }
        let repository = FakeProjectRepository()
        repositoriesByBaseURL[baseURL] = repository
        return repository
    }

    func makeProjectRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> ProjectRepositoryProtocol {
        tokenProvidersByBaseURL[baseURL] = tokenProvider
        return projectRepository(for: baseURL)
    }

    func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeAuthService(baseURL: URL) -> AuthServiceProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeTaskRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        // `sync(_:)` always pulls tasks alongside projects/labels, but
        // nothing in this file asserts on task behavior - a fresh,
        // otherwise-unused fake per call is enough to keep that pull a
        // harmless no-op.
        FakeTaskRepository()
    }

    func makeLabelRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> LabelRepositoryProtocol {
        // `sync(_:)` always pulls labels alongside projects, but nothing in
        // this file asserts on label behavior - a fresh, otherwise-unused
        // fake per call is enough to keep that pull a harmless no-op.
        FakeLabelRepository()
    }

    func makeTaskRelationRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeTaskAttachmentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeUserRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeBucketRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> BucketRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeWebhookRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> WebhookRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeFilterRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> FilterRepositoryProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }
}

private actor FakeReachabilityMonitor: ReachabilityMonitoring {
    var isReachable = false
    /// Set once `SyncCoordinator`'s observation loop has actually
    /// subscribed, so a test can wait for that instead of racing a signal
    /// against a background task that hasn't started yet.
    private(set) var hasSubscriber = false
    private var continuation: AsyncStream<Void>.Continuation?

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.hasSubscriber = true
        }
    }

    func setReachable(_ value: Bool) {
        isReachable = value
    }

    func signalRegained() {
        continuation?.yield()
    }

    /// Ends the stream, so a test's `coordinator.start()` loop can exit on
    /// its own instead of leaking a `Task` parked forever on a continuation
    /// nothing will ever signal again — cancelling the coordinator's `Task`
    /// alone doesn't unblock an in-flight `for await` on this stream.
    func finish() {
        continuation?.finish()
    }
}

struct SyncCoordinatorTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeAccount(host: String) throws -> InstanceAccount {
        try InstanceAccount(displayName: host, baseURL: #require(URL(string: "https://\(host)")))
    }

    /// Polls `condition` instead of a flat sleep, so these tests don't have
    /// to guess how long `SyncCoordinator`'s background task takes to run —
    /// they just wait until its effect is visible, up to a generous bound.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Ends `coordinator`'s observation loop before the test returns. Every
    /// test that calls `start()` must call this too, or the loop's `Task`
    /// leaks forever, parked on a continuation nothing will ever signal
    /// again.
    private func stopObserving(_ coordinator: SyncCoordinator, _ reachability: FakeReachabilityMonitor) async {
        await waitUntil { await reachability.hasSubscriber }
        await reachability.finish()
        await coordinator.stop()
    }

    @Test
    func `start syncs every saved account once reachability is already up`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        await reachability.setReachable(true)
        let accountA = try makeAccount(host: "a.example.com")
        let accountB = try makeAccount(host: "b.example.com")
        try await accountStore.addAccount(accountA, token: "token-a")
        try await accountStore.addAccount(accountB, token: "token-b")
        let repositoryA = factory.projectRepository(for: accountA.baseURL)
        let repositoryB = factory.projectRepository(for: accountB.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.start()

        await waitUntil { repositoryA.fetchProjectsCallCount > 0 && repositoryB.fetchProjectsCallCount > 0 }
        #expect(repositoryA.fetchProjectsCallCount == 1)
        #expect(repositoryB.fetchProjectsCallCount == 1)
        await stopObserving(coordinator, reachability)
    }

    @Test
    func `start syncs again every time reachability is regained`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        let account = try makeAccount(host: "a.example.com")
        try await accountStore.addAccount(account, token: "token-a")
        let repository = factory.projectRepository(for: account.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.start()
        await waitUntil { await reachability.hasSubscriber }
        await reachability.signalRegained()

        await waitUntil { repository.fetchProjectsCallCount > 0 }
        #expect(repository.fetchProjectsCallCount == 1)

        await reachability.signalRegained()
        await waitUntil { repository.fetchProjectsCallCount > 1 }
        #expect(repository.fetchProjectsCallCount == 2)
        await stopObserving(coordinator, reachability)
    }

    @Test
    func `one accounts failure does not stop the others from syncing`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        await reachability.setReachable(true)
        let failingAccount = try makeAccount(host: "down.example.com")
        let healthyAccount = try makeAccount(host: "up.example.com")
        try await accountStore.addAccount(failingAccount, token: "token-down")
        try await accountStore.addAccount(healthyAccount, token: "token-up")
        let failingRepository = factory.projectRepository(for: failingAccount.baseURL)
        failingRepository.fetchError = VikunjaError.network("offline")
        let healthyRepository = factory.projectRepository(for: healthyAccount.baseURL)
        healthyRepository.projects = [Project(id: 1, title: "Groceries")]
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.start()

        // `fetchProjectsCallCount` increments the instant `fetchProjects()`
        // is entered, before `pullProjects()` finishes writing the result —
        // waiting on the row actually landing avoids a race against that
        // still-in-flight write.
        await waitUntil {
            await (try? store.read { db in try ProjectRecord.fetchAll(db) })?.count == 1
        }
        #expect(healthyRepository.fetchProjectsCallCount == 1)
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.accountID) == [healthyAccount.id])
        await stopObserving(coordinator, reachability)
    }

    @Test
    func `syncing two accounts keeps their local projects completely separate`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        await reachability.setReachable(true)
        let accountA = try makeAccount(host: "a.example.com")
        let accountB = try makeAccount(host: "b.example.com")
        try await accountStore.addAccount(accountA, token: "token-a")
        try await accountStore.addAccount(accountB, token: "token-b")
        factory.projectRepository(for: accountA.baseURL).projects = [Project(id: 1, title: "A's project")]
        factory.projectRepository(for: accountB.baseURL).projects = [Project(id: 1, title: "B's project")]
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.start()

        await waitUntil {
            await (try? store.read { db in try ProjectRecord.fetchAll(db) })?.count == 2
        }
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        let rowA = try #require(rows.first { $0.accountID == accountA.id })
        let rowB = try #require(rows.first { $0.accountID == accountB.id })
        #expect(rowA.title == "A's project")
        #expect(rowB.title == "B's project")
        await stopObserving(coordinator, reachability)
    }

    @Test
    func `start does nothing while reachability has never come up`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        let account = try makeAccount(host: "a.example.com")
        try await accountStore.addAccount(account, token: "token-a")
        let repository = factory.projectRepository(for: account.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.start()
        try await Task.sleep(for: .milliseconds(50))

        #expect(repository.fetchProjectsCallCount == 0)
        await stopObserving(coordinator, reachability)
    }

    @Test
    func `syncAllAccounts can be called directly without starting observation`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        let account = try makeAccount(host: "a.example.com")
        try await accountStore.addAccount(account, token: "token-a")
        let repository = factory.projectRepository(for: account.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.syncAllAccounts()

        #expect(repository.fetchProjectsCallCount == 1)
    }

    @Test
    func `sync resolves each account through the injected tokenProvider, not accountStore directly`() async throws {
        // Regression test: `sync(_:)` used to build its own tokenProvider
        // straight off `accountStore.token(forAccountID:)`, which for a
        // password/OIDC account is a JSON credential blob, not a usable
        // bearer token on its own — sending that as-is gets rejected by the
        // server every time, regardless of whether the session is actually
        // still valid. The composition root's injected `tokenProvider` must
        // be what `sync(_:)` actually threads through to the repository it
        // builds, not something resolved internally here.
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = FakeReachabilityMonitor()
        let accountA = try makeAccount(host: "a.example.com")
        try await accountStore.addAccount(accountA, token: "raw-stored-credential-blob")
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { "resolved-token-for-\(account.id)" } },
        )

        await coordinator.syncAllAccounts()

        let tokenProvider = try #require(factory.tokenProvidersByBaseURL[accountA.baseURL])
        let resolvedToken = try await tokenProvider()
        #expect(resolvedToken == "resolved-token-for-\(accountA.id)")
    }
}
