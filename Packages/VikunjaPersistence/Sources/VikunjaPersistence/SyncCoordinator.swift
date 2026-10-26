import Foundation
import VikunjaCore

/// Keeps every saved account's offline queue draining and local cache
/// refreshed whenever the network is reachable, independent of which
/// account is currently active on screen — a backgrounded account would
/// otherwise only ever get a chance to sync while someone happens to be
/// looking at it. Nothing constructs this in production yet (that's the
/// composition root's job, once there's a repository that actually queues
/// mutations for it to drain), so it's unused until that wiring lands.
public actor SyncCoordinator {
    private let localStore: LocalStore
    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let reachability: ReachabilityMonitoring
    private var observationTask: Task<Void, Never>?

    public init(
        localStore: LocalStore,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        reachability: ReachabilityMonitoring,
    ) {
        self.localStore = localStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.reachability = reachability
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
        let repository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL,
            tokenProvider: { [accountStore] in try await accountStore.token(forAccountID: account.id) },
        )
        let engine = SyncEngine(localStore: localStore, projectRepository: repository, accountID: account.id)
        try? await engine.pullProjects()
        try? await engine.drainProjectMutations()
    }
}
