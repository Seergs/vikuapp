import Foundation
import VikunjaCore

/// The single owner of network synchronization for all saved accounts.
/// Every trigger uses the same per-account worker. Overlapping refreshes await
/// its result; writes arriving during a pass request a subsequent pass.
public actor SyncCoordinator {
    private let localStore: LocalStore
    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let reachability: ReachabilityMonitoring
    private let onKanbanCreationRejected: @Sendable (UUID) async -> Void
    private let tokenProvider: @Sendable (InstanceAccount) -> @Sendable () async throws -> String?
    private var observationTask: Task<Void, Never>?

    private struct Work {
        let task: Task<Void, Error>
        var includesAccountPass = false
        var needsAnotherPass = false
        var requestedThreads: Set<EntityID> = []
        var requestedBoards: Set<EntityID> = []
        var pendingBoards: Set<EntityID> = []
        var pendingThreads: Set<EntityID> = []
    }

    private var reloadingAccounts: Set<UUID> = []
    private var workByAccount: [UUID: Work] = [:]

    public init(
        localStore: LocalStore,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        reachability: ReachabilityMonitoring,
        tokenProvider: @escaping @Sendable (InstanceAccount) -> @Sendable () async throws -> String?,
        onKanbanCreationRejected: @escaping @Sendable (UUID) async -> Void = { _ in },
    ) {
        self.localStore = localStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.reachability = reachability
        self.tokenProvider = tokenProvider
        self.onKanbanCreationRejected = onKanbanCreationRejected
    }

    deinit { observationTask?.cancel() }

    public func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            guard let self else { return }
            // The first path report may arrive after startup. The status stream
            // includes it, while a regained-only stream would silently miss it.
            let events = await reachability.reachabilityUpdates()
            var previous: Bool?
            for await isReachable in events {
                guard !Task.isCancelled else { break }
                let shouldSync = isReachable && previous != true
                let regained = previous == false && isReachable
                previous = isReachable
                if shouldSync {
                    // Scheduling must not stop consuming connectivity changes while
                    // a slow account or a request from the old path is still running.
                    _ = await scheduleAllAccounts(retryInFlight: regained)
                }
            }
        }
    }

    public func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Opportunistic triggers isolate failures between accounts. Manual refresh
    /// uses `refresh(accountID:scope:)` and receives the actual failure instead.
    public func syncAllAccounts() async {
        let tasks = await scheduleAllAccounts()
        // All account workers are already running; one stalled instance cannot
        // prevent another account's uploads. Callers still await completion.
        for task in tasks {
            _ = try? await task.value
        }
    }

    private func scheduleAllAccounts(retryInFlight: Bool = false) async -> [Task<Void, Error>] {
        guard await reachability.isReachable,
              let accounts = try? await accountStore.fetchAccounts() else { return [] }
        var tasks: [Task<Void, Error>] = []
        for account in accounts {
            guard !Task.isCancelled else { break }
            guard !reloadingAccounts.contains(account.id) else { continue }
            tasks.append(enqueue(accountID: account.id, scope: .account, afterWrite: retryInFlight))
        }
        return tasks
    }

    public func hasInitialSnapshot(accountID: UUID) async throws -> Bool {
        try await localStore.read { db in
            let states = try SyncStateRecord.fetchAll(db).filter { $0.accountID == accountID }
            return states.contains { $0.entityType == .project }
                && states.contains { $0.entityType == .task }
        }
    }

    public func prepare(accountID: UUID) async throws {
        if try await !hasInitialSnapshot(accountID: accountID) {
            try await refresh(accountID: accountID, scope: .account)
        }
    }

    public func refresh(accountID: UUID, scope: SyncScope) async throws {
        try Task.checkCancellation()
        guard await reachability.isReachable else { throw VikunjaError.offline }
        guard !reloadingAccounts.contains(accountID) else { throw LocalStoreError.accountReloadInProgress }
        let task = enqueue(accountID: accountID, scope: scope, afterWrite: false)
        // A disappearing screen must not cancel work shared with other triggers.
        try await task.value
        try Task.checkCancellation()
    }

    /// Returns as soon as the work is scheduled, never after a network request.
    public func requestSync(accountID: UUID) async {
        guard await reachability.isReachable, !reloadingAccounts.contains(accountID) else { return }
        _ = enqueue(accountID: accountID, scope: .account, afterWrite: true)
    }

    private func enqueue(accountID: UUID, scope: SyncScope, afterWrite: Bool) -> Task<Void, Error> {
        if var work = workByAccount[accountID] {
            if afterWrite || (scope.includesAccount && !work.includesAccountPass) {
                work.needsAnotherPass = true
            }
            work.includesAccountPass = work.includesAccountPass || scope.includesAccount
            if let id = scope.commentTaskID, work.requestedThreads.insert(id).inserted {
                work.pendingThreads.insert(id)
            }
            if let id = scope.kanbanProjectID, work.requestedBoards.insert(id).inserted {
                work.pendingBoards.insert(id)
            }
            workByAccount[accountID] = work
            return work.task
        }
        let task = Task { try await self.run(accountID: accountID) }
        var work = Work(task: task)
        work.includesAccountPass = scope.includesAccount
        work.needsAnotherPass = scope.includesAccount
        if let id = scope.commentTaskID {
            work.requestedThreads.insert(id)
            work.pendingThreads.insert(id)
        }
        if let id = scope.kanbanProjectID {
            work.requestedBoards.insert(id)
            work.pendingBoards.insert(id)
        }
        workByAccount[accountID] = work
        return task
    }

    private func run(accountID: UUID) async throws {
        defer { workByAccount[accountID] = nil }
        guard let account = try await accountStore.fetchAccounts().first(where: { $0.id == accountID }) else {
            throw VikunjaError.notFound
        }
        let engine = makeEngine(account)
        var failure: (any Error)?
        var boardFailures: [EntityID: any Error] = [:]
        var threadFailures: [EntityID: any Error] = [:]
        while true {
            try Task.checkCancellation()
            let needsPass = workByAccount[accountID]?.needsAnotherPass ?? false
            workByAccount[accountID]?.needsAnotherPass = false
            if needsPass {
                do {
                    try await engine.synchronize()
                    failure = nil
                } catch { failure = error }
            }
            // Capture pending detail work after the account pass has populated
            // task identities, including tasks that were just created offline.
            let threads = workByAccount[accountID]?.pendingThreads ?? []
            workByAccount[accountID]?.pendingThreads = []
            for id in threads {
                try Task.checkCancellation()
                do {
                    try await engine.pullComments(taskID: id)
                    threadFailures[id] = nil
                } catch { threadFailures[id] = error }
                workByAccount[accountID]?.requestedThreads.remove(id)
            }
            boardFailures = await pullPendingBoards(account, previousFailures: boardFailures)
            if workByAccount[accountID]?.pendingBoards.isEmpty == false {
                continue
            }
            if workByAccount[accountID]?.needsAnotherPass == true {
                continue
            }
            if workByAccount[accountID]?.pendingThreads.isEmpty == false {
                continue
            }
            break
        }
        if let failure = failure ?? threadFailures.values.first ?? boardFailures.values.first {
            throw failure
        }
    }

    private func pullPendingBoards(
        _ account: InstanceAccount, previousFailures: [EntityID: any Error],
    ) async -> [EntityID: any Error] {
        let boards = workByAccount[account.id]?.pendingBoards ?? []
        workByAccount[account.id]?.pendingBoards = []
        var failures = previousFailures
        for id in boards {
            guard !Task.isCancelled else { break }
            do {
                try await makeEngine(account).pullKanban(projectID: id)
                failures[id] = nil
            } catch { failures[id] = error }
            workByAccount[account.id]?.requestedBoards.remove(id)
        }
        return failures
    }

    /// Staging reuses the ordinary pull path, but never drains the live queue.
    public func reloadFromServer(accountID: UUID) async throws {
        try Task.checkCancellation()
        guard reloadingAccounts.insert(accountID).inserted else { throw LocalStoreError.accountReloadInProgress }
        defer { reloadingAccounts.remove(accountID) }
        guard await reachability.isReachable else { throw VikunjaError.offline }
        let previousWork = workByAccount[accountID]?.task
        previousWork?.cancel()
        _ = try? await previousWork?.value
        try Task.checkCancellation()
        guard let account = try await accountStore.fetchAccounts().first(where: { $0.id == accountID }) else {
            throw VikunjaError.notFound
        }
        let original = try await localStore.beginAccountReload(accountID: accountID)
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let staging = try LocalStore(directory: directory)
            try await staging.write { db in try original.seedIdentities(db: db) }
            try await makeEngine(account, store: staging).downloadReplacement(original: original)
            try Task.checkCancellation()
            let replacement = try await staging.read { db in try AccountSnapshot(accountID: accountID, db: db) }
            try await localStore.replaceAccount(accountID: accountID, with: replacement)
            await localStore.endAccountReload(accountID: accountID)
        } catch {
            await localStore.endAccountReload(accountID: accountID)
            throw error
        }
    }

    private func makeEngine(_ account: InstanceAccount, store: LocalStore? = nil) -> SyncEngine {
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
        let commentRepository = clientFactory.makeTaskCommentRepository(
            baseURL: account.baseURL,
            tokenProvider: resolvedTokenProvider,
        )
        let filterRepository = clientFactory.makeFilterRepository(
            baseURL: account.baseURL,
            tokenProvider: resolvedTokenProvider,
        )
        return SyncEngine(
            localStore: store ?? localStore,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            taskRepository: taskRepository,
            relationRepository: relationRepository,
            commentRepository: commentRepository,
            filterRepository: filterRepository,
            accountID: account.id,
            bucketRepository: clientFactory.makeBucketRepository(
                baseURL: account.baseURL, tokenProvider: resolvedTokenProvider,
            ),
            capabilityProvider: clientFactory.makeCapabilityProvider(baseURL: account.baseURL),
            onKanbanCreationRejected: onKanbanCreationRejected,
        )
    }
}

/// Account binding is immutable: an account switch cannot redirect an in-flight
/// screen or repository command to another account.
public struct AccountSync: SyncTriggering, SyncRequesting, LocalDataObserving, AccountReloading {
    private let accountID: UUID
    private let coordinator: SyncCoordinator
    private let localStore: LocalStore

    public init(accountID: UUID, coordinator: SyncCoordinator, localStore: LocalStore) {
        self.accountID = accountID
        self.coordinator = coordinator
        self.localStore = localStore
    }

    public func hasInitialSnapshot() async throws -> Bool {
        try await coordinator.hasInitialSnapshot(accountID: accountID)
    }

    public func prepare() async throws {
        try await coordinator.prepare(accountID: accountID)
    }

    public func refresh(scope: SyncScope) async throws {
        try await coordinator.refresh(accountID: accountID, scope: scope)
    }

    public func reloadFromServer() async throws {
        try await coordinator.reloadFromServer(accountID: accountID)
    }

    public func requestSync() async {
        await coordinator.requestSync(accountID: accountID)
    }

    public func localChanges() async -> AsyncThrowingStream<Void, Error> {
        await localStore.observeChanges(accountID: accountID)
    }
}
