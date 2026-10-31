import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

actor FakeAccountStore: AccountStoreProtocol {
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
final class FakeInstanceClientFactory: InstanceClientFactoryProtocol, @unchecked Sendable {
    let boardRepository = KanbanDownloadFake(KanbanDownload(
        viewID: 10, mode: "manual", filterQuery: "", defaultBucketID: nil, doneBucketID: nil, buckets: [],
    ))
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

    private var tasksByBaseURL: [URL: FakeTaskRepository] = [:]
    private var commentsByBaseURL: [URL: FakeTaskCommentRepository] = [:]

    func taskRepository(for baseURL: URL) -> FakeTaskRepository {
        if let existing = tasksByBaseURL[baseURL] {
            return existing
        }
        let repository = FakeTaskRepository()
        tasksByBaseURL[baseURL] = repository
        return repository
    }

    func commentRepository(for baseURL: URL) -> FakeTaskCommentRepository {
        if let existing = commentsByBaseURL[baseURL] {
            return existing
        }
        let repository = FakeTaskCommentRepository()
        commentsByBaseURL[baseURL] = repository
        return repository
    }

    func makeCapabilityProvider(baseURL: URL) -> CapabilityProvider {
        KanbanCapabilities()
    }

    func makeAuthService(baseURL: URL) -> AuthServiceProtocol {
        fatalError("not used by SyncCoordinatorTests")
    }

    func makeTaskRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        taskRepository(for: baseURL)
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
        // `sync(_:)` always pulls relations alongside tasks, but nothing in
        // this file asserts on relation behavior - a fresh, otherwise-unused
        // fake per call is enough to keep that pull a harmless no-op.
        FakeTaskRelationRepository()
    }

    func makeTaskCommentRepository(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        commentRepository(for: baseURL)
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
        boardRepository
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
        let repository = FakeFilterRepository()
        repository.filters[2] = SavedFilterDetail(
            id: 2,
            title: "Filter",
            description: "",
            isFavorite: false,
            query: "done = false",
        )
        return repository
    }
}

actor CoordinatorReachabilityMonitor: ReachabilityMonitoring {
    private var reachable: Bool
    private var hasInitialReport: Bool
    private var hasReadStatus = false
    private var hasStatusSubscriber = false
    var isReachable: Bool {
        hasReadStatus = true
        return reachable
    }

    var readyForFirstReport: Bool {
        hasReadStatus || hasStatusSubscriber
    }

    init(isReachable: Bool = true, hasInitialReport: Bool = true) {
        self.reachable = isReachable
        self.hasInitialReport = hasInitialReport
    }

    /// Set once `SyncCoordinator`'s observation loop has actually
    /// subscribed, so a test can wait for that instead of racing a signal
    /// against a background task that hasn't started yet.
    private(set) var hasSubscriber = false
    private var continuation: AsyncStream<Void>.Continuation?
    private var statusContinuation: AsyncStream<Bool>.Continuation?

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.hasSubscriber = true
        }
    }

    func reachabilityUpdates() async -> AsyncStream<Bool> {
        AsyncStream { continuation in
            statusContinuation = continuation
            hasSubscriber = true
            hasStatusSubscriber = true
            if hasInitialReport {
                continuation.yield(reachable)
            }
        }
    }

    func setReachable(_ value: Bool) {
        reachable = value
        hasInitialReport = true
        statusContinuation?.yield(value)
    }

    func signalRegained() {
        reachable = true
        hasInitialReport = true
        continuation?.yield()
        statusContinuation?.yield(false)
        statusContinuation?.yield(true)
    }

    /// Ends the stream, so a test's `coordinator.start()` loop can exit on
    /// its own instead of leaking a `Task` parked forever on a continuation
    /// nothing will ever signal again — cancelling the coordinator's `Task`
    /// alone doesn't unblock an in-flight `for await` on this stream.
    func finish() {
        continuation?.finish()
        statusContinuation?.finish()
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
    private func stopObserving(_ coordinator: SyncCoordinator, _ reachability: CoordinatorReachabilityMonitor) async {
        await waitUntil { await reachability.hasSubscriber }
        await reachability.finish()
        await coordinator.stop()
    }

    @Test(arguments: [SyncScope.account, .task(.remote(5)), .comments(.remote(5))])
    func `offline refresh leaves local changes pending and reconnect sends them`(scope: SyncScope) async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor(isReachable: false)
        let account = try makeAccount(host: "offline.example.com")
        try await accountStore.addAccount(account, token: "token")
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { _ in { "token" } },
        )
        let repository = OfflineProjectRepository(
            localStore: store, accountID: account.id, syncRequester: NoopKanbanSyncRequester(),
        )
        let project = try await repository.create(Project(id: .local(UUID()), title: "Offline project"))

        await #expect(throws: VikunjaError.offline) {
            try await coordinator.refresh(accountID: account.id, scope: scope)
        }

        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued.first?.status == .pending)
        #expect(queued.first?.retryCount == 0)
        #expect(queued.first?.lastError == nil)
        let statuses = try await store.pendingSyncStatuses(accountID: account.id)
        #expect(statuses[SyncItemKey(kind: .project, id: project.id)] == .pending)
        #expect(factory.projectRepository(for: account.baseURL).fetchProjectsCallCount == 0)

        await reachability.setReachable(true)
        try await coordinator.refresh(accountID: account.id, scope: .account)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
        #expect(factory.projectRepository(for: account.baseURL).createdProjects.count == 1)
    }

    @Test func `overlapping board refreshes share one download`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let account = try makeAccount(host: "kanban.example.com")
        try await accountStore.addAccount(account, token: "test")
        factory.projectRepository(for: account.baseURL).projects = [Project(id: 1, title: "Work")]
        try await store.write { db in
            try ProjectRecord(
                localID: UUID(),
                accountID: account.id,
                remoteID: 1,
                title: "Work",
                description: nil,
                isArchived: false,
                isFavorite: false,
                parentProjectLocalID: nil,
                position: 0,
                hexColor: "",
                serverUpdatedAt: nil,
            ).insert(db)
        }
        let coordinator = SyncCoordinator(
            localStore: store,
            accountStore: accountStore,
            clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(),
            tokenProvider: { _ in { nil } },
        )
        await factory.boardRepository.slowDown()
        let first = Task { try await coordinator.refresh(accountID: account.id, scope: .kanban(projectID: .remote(1))) }
        await waitUntil { await factory.boardRepository.calls == 1 }
        try await coordinator.refresh(accountID: account.id, scope: .kanban(projectID: .remote(1)))
        try await first.value
        #expect(await factory.boardRepository.calls == 1)
        #expect(factory.projectRepository(for: account.baseURL).fetchProjectsCallCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `start syncs every saved account once reachability is already up`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor()
        await reachability.setReachable(true)
        let accountA = try makeAccount(host: "a.example.com")
        let accountB = try makeAccount(host: "b.example.com")
        try await accountStore.addAccount(accountA, token: "token-a")
        try await accountStore.addAccount(accountB, token: "token-b")
        let repositoryA = factory.projectRepository(for: accountA.baseURL)
        let repositoryB = factory.projectRepository(for: accountB.baseURL)
        let (secondAccountFetch, continuation) = AsyncStream<Void>.makeStream()
        repositoryB.onFetchProjects = {
            continuation.yield(())
            continuation.finish()
        }
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        await coordinator.start()

        // Account workers may start in either order; await both requests.
        var fetches = secondAccountFetch.makeAsyncIterator()
        let received = await fetches.next()
        #expect(received != nil)
        await waitUntil { repositoryA.fetchProjectsCallCount == 1 }
        #expect(repositoryA.fetchProjectsCallCount == 1)
        #expect(repositoryB.fetchProjectsCallCount == 1)
        await stopObserving(coordinator, reachability)
    }

    @Test
    func `start syncs again every time reachability is regained`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor(isReachable: false)
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
        let reachability = CoordinatorReachabilityMonitor()
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

        // This verifies the completed multi-account result. Await the command
        // directly; the start test separately verifies background scheduling.
        await coordinator.syncAllAccounts()

        #expect(healthyRepository.fetchProjectsCallCount == 1)
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.accountID) == [healthyAccount.id])
    }

    @Test
    func `syncing two accounts keeps their local projects completely separate`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor()
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

        // This verifies the completed multi-account result. Await the command
        // directly; the start test separately verifies background scheduling.
        await coordinator.syncAllAccounts()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        let rowA = try #require(rows.first { $0.accountID == accountA.id })
        let rowB = try #require(rows.first { $0.accountID == accountB.id })
        #expect(rowA.title == "A's project")
        #expect(rowB.title == "B's project")
    }

    @Test
    func `start does nothing while reachability has never come up`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor(isReachable: false)
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
        let reachability = CoordinatorReachabilityMonitor()
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
    func `an overlapping sync for the same account is skipped instead of racing the first`() async throws {
        // Regression test: foregrounding the app and regaining reachability
        // at nearly the same moment each fire their own `syncAllAccounts()`
        // independently. Without a guard, both calls build their own
        // `SyncEngine` and can both drain the very same still-pending
        // mutation before either's network call returns - duplicating a
        // create server-side. The second overlapping call must be a no-op
        // while the first is still in flight for that account.
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor()
        let account = try makeAccount(host: "a.example.com")
        try await accountStore.addAccount(account, token: "token-a")
        let repository = factory.projectRepository(for: account.baseURL)
        repository.fetchDelay = .milliseconds(200)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { try await accountStore.token(forAccountID: account.id) } },
        )

        async let first: Void = coordinator.syncAllAccounts()
        await waitUntil { repository.fetchProjectsCallCount > 0 }
        async let second: Void = coordinator.syncAllAccounts()
        _ = await (first, second)

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
        let reachability = CoordinatorReachabilityMonitor()
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

    @Test
    func `manual refresh downloads external renames after the first sync`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accounts = FakeAccountStore()
        let account = try makeAccount(host: "refresh.example.com")
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let remote = factory.projectRepository(for: account.baseURL)
        remote.projects = [Project(id: -3, title: "Original filter")]
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(), tokenProvider: { _ in { "token" } },
        )
        try await coordinator.refresh(accountID: account.id, scope: .account)
        remote.projects = [Project(id: -3, title: "Renamed on web")]
        try await coordinator.refresh(accountID: account.id, scope: .account)
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.title) == ["Renamed on web"])
        #expect(remote.fetchProjectsCallCount == 2)
    }

    @Test
    func `manual refresh reports failure and preserves cached projects`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accounts = FakeAccountStore()
        let account = try makeAccount(host: "refresh.example.com")
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let remote = factory.projectRepository(for: account.baseURL)
        remote.projects = [Project(id: 1, title: "Cached")]
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(), tokenProvider: { _ in { "token" } },
        )
        try await coordinator.refresh(accountID: account.id, scope: .account)
        remote.fetchError = VikunjaError.network("offline")
        await #expect(throws: VikunjaError.network("offline")) {
            try await coordinator.refresh(accountID: account.id, scope: .account)
        }
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.title) == ["Cached"])
    }

    @Test
    func `manual refresh waits for an automatic sync instead of returning stale cache`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accounts = FakeAccountStore()
        let account = try makeAccount(host: "refresh.example.com")
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let remote = factory.projectRepository(for: account.baseURL)
        remote.projects = [Project(id: 1, title: "Arrived")]
        remote.fetchDelay = .milliseconds(150)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(), tokenProvider: { _ in { "token" } },
        )
        async let automatic: Void = coordinator.syncAllAccounts()
        await waitUntil { remote.fetchProjectsCallCount == 1 }
        try await coordinator.refresh(accountID: account.id, scope: .account)
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.title) == ["Arrived"])
        await automatic
        #expect(remote.fetchProjectsCallCount == 1)
    }

    @Test
    func `a write during a sync schedules another pass without blocking the local save`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accounts = FakeAccountStore()
        let account = try makeAccount(host: "refresh.example.com")
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let remote = factory.projectRepository(for: account.baseURL)
        remote.fetchDelay = .milliseconds(150)
        let reachability = CoordinatorReachabilityMonitor()
        await reachability.setReachable(true)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: reachability, tokenProvider: { _ in { "token" } },
        )
        let sync = AccountSync(accountID: account.id, coordinator: coordinator, localStore: store)
        let repository = OfflineProjectRepository(localStore: store, accountID: account.id, syncRequester: sync)
        async let automatic: Void = coordinator.syncAllAccounts()
        await waitUntil { remote.fetchProjectsCallCount == 1 }
        let created = try await repository.create(Project(id: .local(UUID()), title: "Saved immediately"))
        #expect(created.id.remoteValue == nil)
        #expect(remote.createdProjects.isEmpty)
        await automatic
        #expect(remote.fetchProjectsCallCount == 2)
        #expect(remote.createdProjects.count == 1)
        #expect(try await repository.fetchProjects().map(\.title) == ["Saved immediately"])
    }

    @Test
    func `an upload failure is not reported as a successful refresh`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accounts = FakeAccountStore()
        let account = try makeAccount(host: "refresh.example.com")
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let remote = factory.projectRepository(for: account.baseURL)
        remote.createError = VikunjaError.network("offline")
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(), tokenProvider: { _ in { "token" } },
        )
        let sync = AccountSync(accountID: account.id, coordinator: coordinator, localStore: store)
        let repository = OfflineProjectRepository(localStore: store, accountID: account.id, syncRequester: sync)
        _ = try await repository.create(Project(id: .local(UUID()), title: "Pending"))
        await #expect(throws: (any Error).self) {
            try await sync.refresh(scope: .account)
        }
        #expect(try await repository.fetchProjects().map(\.title) == ["Pending"])
        let pending = try await store.pendingSyncOperations(accountID: account.id)
        #expect(pending.count == 1)
    }

    @Test
    func `opening a cached task explicitly refreshes its thread without re-pulling the account`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accounts = FakeAccountStore()
        let account = try makeAccount(host: "comments.example.com")
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let projects = factory.projectRepository(for: account.baseURL)
        projects.projects = [Project(id: 1, title: "Project")]
        factory.taskRepository(for: account.baseURL).tasks = [VikunjaTask(id: 5, title: "Task", projectID: 1)]
        let comments = factory.commentRepository(for: account.baseURL)
        comments.comments = [TaskComment(
            id: .remote(21), comment: "Thread", author: User(id: 1, username: "me"), created: Date(), updated: Date(),
        )]
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(), tokenProvider: { _ in { "token" } },
        )
        try await coordinator.refresh(accountID: account.id, scope: .account)
        #expect(comments.fetchedTaskIDs.isEmpty)
        try await coordinator.refresh(accountID: account.id, scope: .comments(.remote(5)))
        #expect(projects.fetchProjectsCallCount == 1)
        #expect(comments.fetchedTaskIDs == [.remote(5)])
        #expect(try await store.read { db in try TaskCommentRecord.fetchAll(db).map(\.comment) } == ["Thread"])
        try await coordinator.refresh(accountID: account.id, scope: .task(.remote(5)))
        #expect(projects.fetchProjectsCallCount == 2)
        #expect(comments.fetchedTaskIDs == [.remote(5), .remote(5)])
    }

    @Test(arguments: [false, true])
    func `manual board refresh uploads offline creations before showing success or capacity recovery`(full: Bool) async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor()
        let account = try makeAccount(host: "offline-board.example.com")
        try await accountStore.addAccount(account, token: "token")
        factory.projectRepository(for: account.baseURL).projects = [Project(id: 1, title: "Work")]
        await factory.boardRepository.set(KanbanDownload(
            viewID: 10, mode: "manual", filterQuery: "", defaultBucketID: 20, doneBucketID: nil,
            buckets: [KanbanBucket(id: 20, title: "Limited", limit: 2)],
        ))
        await factory.boardRepository.acceptCreations(failure: full ? .bucketFull : nil)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory, reachability: reachability,
            tokenProvider: { _ in { "token" } },
        )
        try await coordinator.refresh(accountID: account.id, scope: .account)
        try await coordinator.refresh(accountID: account.id, scope: .kanban(projectID: .remote(1)))
        await reachability.setReachable(false)
        let board = OfflineKanbanBoardRepository(
            localStore: store, accountID: account.id, syncRequester: NoopKanbanSyncRequester(),
            reachability: reachability,
        )
        let task = try await board.createTask(title: "Offline", projectID: .remote(1), viewID: 10, bucketID: 20)
        if !full {
            _ = try await board.createTask(title: "Second offline", projectID: .remote(1), viewID: 10, bucketID: 20)
        }
        await reachability.setReachable(true)
        if full {
            await #expect(throws: SyncIncompleteError.self) {
                try await coordinator.refresh(accountID: account.id, scope: .kanban(projectID: .remote(1)))
            }
        } else {
            try await coordinator.refresh(accountID: account.id, scope: .kanban(projectID: .remote(1)))
        }
        #expect(await factory.boardRepository.creationCalls == (full ? 1 : 2))
        let pending = try await store.pendingSyncOperations(accountID: account.id)
        if full {
            #expect(pending.count == 1)
            #expect(pending.first?.canRecoverKanbanCreation == true)
        } else {
            #expect(pending.isEmpty)
            let tasks = OfflineTaskRepository(
                localStore: store, accountID: account.id, syncRequester: NoopKanbanSyncRequester(),
            )
            #expect(try await tasks.fetchTask(id: task.id).id == .remote(500))
            let identities = try await Set(tasks.fetchTasks(projectID: .remote(1)).map(\.id))
            #expect(identities == [.remote(500), .remote(501)])
        }
    }

    @Test func `a stalled account cannot prevent another account from synchronizing`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let first = try makeAccount(host: "stalled.example.com")
        let second = try makeAccount(host: "healthy.example.com")
        try await accountStore.addAccount(first, token: "token")
        try await accountStore.addAccount(second, token: "token")
        let (release, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        factory.projectRepository(for: first.baseURL).beforeFetchResponse = { for await _ in release {} }
        let healthy = factory.projectRepository(for: second.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory,
            reachability: CoordinatorReachabilityMonitor(), tokenProvider: { _ in { "token" } },
        )
        let pass = Task { await coordinator.syncAllAccounts() }
        await waitUntil { healthy.fetchProjectsCallCount == 1 }
        #expect(healthy.fetchProjectsCallCount == 1)
        continuation.finish()
        await pass.value
    }

    @Test func `reconnection is processed while another account still has an unfinished request`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor(isReachable: false)
        let first = try makeAccount(host: "stalled.example.com")
        let second = try makeAccount(host: "healthy.example.com")
        try await accountStore.addAccount(first, token: "token")
        try await accountStore.addAccount(second, token: "token")
        let (release, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        factory.projectRepository(for: first.baseURL).beforeFetchResponse = { for await _ in release {} }
        let healthy = factory.projectRepository(for: second.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory,
            reachability: reachability, tokenProvider: { _ in { "token" } },
        )
        await coordinator.start()
        await waitUntil { await reachability.hasSubscriber }
        await reachability.signalRegained()
        await waitUntil { healthy.fetchProjectsCallCount == 1 }
        await reachability.setReachable(false)
        let projects = OfflineProjectRepository(
            localStore: store, accountID: second.id, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await projects.create(Project(id: .local(UUID()), title: "Offline"))
        await reachability.signalRegained()
        await waitUntil { healthy.createdProjects.count == 1 }
        #expect(healthy.createdProjects.count == 1)
        continuation.finish()
        await coordinator.syncAllAccounts()
        await stopObserving(coordinator, reachability)
    }

    @Test func `the initial online report starts synchronization even when startup had no path yet`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountStore = FakeAccountStore()
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor(isReachable: false, hasInitialReport: false)
        let account = try makeAccount(host: "first-path.example.com")
        try await accountStore.addAccount(account, token: "token")
        let remote = factory.projectRepository(for: account.baseURL)
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accountStore, clientFactory: factory,
            reachability: reachability, tokenProvider: { _ in { "token" } },
        )
        await coordinator.start()
        await waitUntil { await reachability.readyForFirstReport }
        // This is an initial status, not a transition from a previously known offline path.
        await reachability.setReachable(true)
        await waitUntil { remote.fetchProjectsCallCount == 1 }
        #expect(remote.fetchProjectsCallCount == 1)
        await stopObserving(coordinator, reachability)
    }
}
