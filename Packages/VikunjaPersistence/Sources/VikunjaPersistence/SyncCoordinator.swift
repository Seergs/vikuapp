import Foundation
import VikunjaCore

/// Keeps every saved account's offline queue draining and local cache
/// refreshed whenever the network is reachable, independent of which
/// account is currently active on screen — a backgrounded account would
/// otherwise only ever get a chance to sync while someone happens to be
/// looking at it.
public actor SyncCoordinator {
    private let localStore: LocalStore
    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let reachability: ReachabilityMonitoring
    /// Resolves a currently-valid bearer credential for an account — handed
    /// in by the composition root rather than read straight off
    /// `accountStore.token(forAccountID:)` here, since a password/OIDC
    /// account's stored credential is an opaque JSON blob (access + refresh
    /// token), not a usable bearer token on its own; only the app target's
    /// session-refresh logic knows how to turn it into one.
    private let tokenProvider: @Sendable (InstanceAccount) -> @Sendable () async throws -> String?
    private var observationTask: Task<Void, Never>?
    /// Accounts with a `sync(_:)` already in flight — `syncAllAccounts()`
    /// can itself be triggered more than once in close succession (going
    /// reachable fires `reachabilityRegained()`, and foregrounding the app
    /// fires its own call independently), and each call builds a brand new
    /// `SyncEngine` with no shared state between them. Without this guard,
    /// two overlapping calls can both read the same still-pending `create`
    /// mutation (the first hasn't gotten its network response back yet, so
    /// it's not deleted from the queue) and both push it, creating the same
    /// task twice server-side.
    private var syncingAccountIDs: Set<UUID> = []

    public init(
        localStore: LocalStore,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        reachability: ReachabilityMonitoring,
        tokenProvider: @escaping @Sendable (InstanceAccount) -> @Sendable () async throws -> String?,
    ) {
        self.localStore = localStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.reachability = reachability
        self.tokenProvider = tokenProvider
    }

    deinit {
        observationTask?.cancel()
    }

    /// Starts opportunistic syncing: once immediately if the network is
    /// already up, then again every time it transitions from unreachable
    /// to reachable. Idempotent — calling it again while already observing
    /// has no effect.
    public func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            guard let self else { return }
            await observeReachability()
        }
    }

    /// Stops observing reachability. Any sync pass already in flight still
    /// finishes; only future reachability transitions are ignored.
    public func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Drains then re-pulls every saved account's projects, one account at
    /// a time. One account's failure (e.g. a revoked token) never stops the
    /// others from syncing.
    public func syncAllAccounts() async {
        let accounts = await (try? accountStore.fetchAccounts()) ?? []
        for account in accounts {
            await sync(account)
        }
    }

    private func observeReachability() async {
        if await reachability.isReachable {
            await syncAllAccounts()
        }
        for await _ in await reachability.reachabilityRegained() {
            await syncAllAccounts()
        }
    }

    private func sync(_ account: InstanceAccount) async {
        guard syncingAccountIDs.insert(account.id).inserted else { return }
        defer { syncingAccountIDs.remove(account.id) }
        let resolvedTokenProvider = tokenProvider(account)
        let projectRepository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: resolvedTokenProvider,
        )
        let labelRepository = clientFactory.makeLabelRepository(
            baseURL: account.baseURL,
            tokenProvider: resolvedTokenProvider,
        )
        let taskRepository = clientFactory.makeTaskRepository(
            baseURL: account.baseURL,
            tokenProvider: resolvedTokenProvider,
        )
        let relationRepository = clientFactory.makeTaskRelationRepository(
            baseURL: account.baseURL,
            tokenProvider: resolvedTokenProvider,
        )
        let engine = SyncEngine(
            localStore: localStore,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            taskRepository: taskRepository,
            relationRepository: relationRepository,
            accountID: account.id,
        )
        try? await engine.pullProjects()
        try? await engine.drainProjectMutations()
        try? await engine.pullLabels()
        try? await engine.drainLabelMutations()
        try? await engine.pullTasks()
        try? await engine.drainTaskMutations()
    }
}
