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
    private let onAccountDataChanged: @Sendable () async -> Void
    private let onKanbanCreationRejected: @Sendable (UUID) async -> Void
    private let tokenProvider: @Sendable (InstanceAccount) -> @Sendable () async throws -> String?
    private var observationTask: Task<Void, Never>?

    private struct BoardRefreshFailures: Error {
        let errors: [SyncScope: any Error]
    }

    private struct Work {
        let task: Task<Void, Error>
        var includesAccountPass = false
        var needsAnotherPass = false
        var requestedThreads: Set<EntityID> = []
        var requestedBoards: Set<SyncScope> = []
        var pendingBoards: Set<SyncScope> = []
        var pendingThreads: Set<EntityID> = []
        var priorityUploads: Set<EntityID> = []
    }

    /// A saved credential must receive a successful pass even with an existing
    /// snapshot. Revisions prevent an older pass acknowledging a newer login.
    private var authenticationRefreshes: [UUID: UUID] = [:]
    private var reloadingAccounts: Set<UUID> = []
    private var workByAccount: [UUID: Work] = [:]
    private var reschedulingAccounts: Set<UUID> = []

    public init(
        localStore: LocalStore,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        reachability: ReachabilityMonitoring,
        tokenProvider: @escaping @Sendable (InstanceAccount) -> @Sendable () async throws -> String?,
        onKanbanCreationRejected: @escaping @Sendable (UUID) async -> Void = { _ in },
        onAccountDataChanged: @escaping @Sendable () async -> Void = {},
    ) {
        self.localStore = localStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.reachability = reachability
        self.tokenProvider = tokenProvider
        self.onKanbanCreationRejected = onKanbanCreationRejected
        self.onAccountDataChanged = onAccountDataChanged
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
        guard localStore.executionLifecycle?.isSuspended != true, await reachability.isReachable,
              let accounts = try? await accountStore.fetchAccounts() else { return [] }
        var tasks: [Task<Void, Error>] = []
        for account in accounts {
            guard !Task.isCancelled else { break }
            guard !reloadingAccounts.contains(account.id) else { continue }
            if let previous = workByAccount[account.id]?.task, previous.isCancelled {
                tasks.append(Task {
                    _ = await previous.result
                    try await self.refresh(accountID: account.id, scope: .account)
                })
            } else {
                tasks.append(enqueue(accountID: account.id, scope: .account, afterWrite: retryInFlight))
            }
        }
        return tasks
    }

    public func credentialsDidChange(accountID: UUID) async {
        authenticationRefreshes[accountID] = UUID()
        await requestSync(accountID: accountID)
    }

    public func hasInitialSnapshot(accountID: UUID) async throws -> Bool {
        guard authenticationRefreshes[accountID] == nil else { return false }
        return try await localStore.read { db in
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

    public func refresh(
        accountID: UUID, scope: SyncScope, cancelWorkerOnCancellation: Bool = false,
    ) async throws {
        try Task.checkCancellation()
        try localStore.executionLifecycle?.checkAccess()
        guard await !reachability.isKnownOffline else { throw VikunjaError.offline }
        guard !reloadingAccounts.contains(accountID) else { throw LocalStoreError.accountReloadInProgress }
        await finishCancelledWork(accountID: accountID)
        try localStore.executionLifecycle?.checkAccess()
        guard !reloadingAccounts.contains(accountID) else { throw LocalStoreError.accountReloadInProgress }
        let task = enqueue(accountID: accountID, scope: scope, afterWrite: false)
        // A disappearing screen must not cancel work shared with other triggers.
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                if cancelWorkerOnCancellation {
                    task.cancel()
                }
            }
        } catch let failure as BoardRefreshFailures {
            if let error = failure.errors[scope] {
                throw error
            }
        } catch {
            if task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
        try Task.checkCancellation()
    }

    /// Returns as soon as the work is scheduled, never after a network request.
    public func requestSync(accountID: UUID) async {
        guard localStore.executionLifecycle?.isSuspended != true,
              await reachability.isReachable, !reloadingAccounts.contains(accountID) else { return }
        if let previous = workByAccount[accountID]?.task, previous.isCancelled {
            // Local saves must not await a cancelled request that is still
            // unwinding. Coalesce writes into one reschedule after it settles.
            guard reschedulingAccounts.insert(accountID).inserted else { return }
            Task {
                _ = await previous.result
                self.reschedulingAccounts.remove(accountID)
                await self.requestSync(accountID: accountID)
            }
            return
        }
        _ = enqueue(accountID: accountID, scope: .account, afterWrite: true)
    }

    /// Keep the background execution assertion until the actual shared workers
    /// settle. New work arriving before suspension is included on the next loop.
    public func waitForCurrentWork() async {
        if let lifecycle = localStore.executionLifecycle {
            await lifecycle.waitForWorkers()
            return
        }
        while !workByAccount.isEmpty, !Task.isCancelled {
            let tasks = workByAccount.values.map(\.task)
            for task in tasks {
                _ = await task.result
            }
        }
    }

    private func finishCancelledWork(accountID: UUID) async {
        if let task = workByAccount[accountID]?.task, task.isCancelled {
            _ = await task.result
        }
    }

    private func enqueue(accountID: UUID, scope: SyncScope, afterWrite: Bool) -> Task<Void, Error> {
        if var work = workByAccount[accountID] {
            if afterWrite || (scope.includesAccount && !work.includesAccountPass) {
                work.needsAnotherPass = true
            }
            work.includesAccountPass = work.includesAccountPass || scope.includesAccount
            if let id = scope.uploadTaskID {
                work.priorityUploads.insert(id)
            }
            if let id = scope.commentTaskID, work.requestedThreads.insert(id).inserted {
                work.pendingThreads.insert(id)
            }
            if case .kanban = scope, work.requestedBoards.insert(scope).inserted {
                work.pendingBoards.insert(scope)
            }
            workByAccount[accountID] = work
            return work.task
        }
        let id = UUID()
        let lifecycle = localStore.executionLifecycle
        let task = Task {
            defer { lifecycle?.untrack(id) }
            try await self.run(accountID: accountID)
        }
        lifecycle?.track(task, id: id)
        var work = Work(task: task)
        work.includesAccountPass = scope.includesAccount
        work.needsAnotherPass = scope.includesAccount
        if let id = scope.uploadTaskID {
            work.priorityUploads.insert(id)
        }
        if let id = scope.commentTaskID {
            work.requestedThreads.insert(id)
            work.pendingThreads.insert(id)
        }
        if case .kanban = scope {
            work.requestedBoards.insert(scope)
            work.pendingBoards.insert(scope)
        }
        workByAccount[accountID] = work
        return task
    }

    private func run(accountID: UUID) async throws {
        defer { workByAccount[accountID] = nil }
        let ownership = SyncOwnership(accountID: accountID)
        try await ownership.acquire(in: localStore)
        let before = try? await LocalTaskSnapshotReader(localStore: localStore).loadSnapshot(accountID: accountID)
        do {
            try await runOwned(accountID: accountID)
            await ownership.release(in: localStore)
            await notifyDataChange(accountID: accountID, before: before)
        } catch {
            await ownership.release(in: localStore)
            await notifyDataChange(accountID: accountID, before: before)
            throw error
        }
    }

    private func notifyDataChange(accountID: UUID, before: LocalTaskSnapshot?) async {
        guard !Task.isCancelled else { return }
        let after = try? await LocalTaskSnapshotReader(localStore: localStore).loadSnapshot(accountID: accountID)
        if before?.tasks != after?.tasks || before?.projects != after?.projects
            || before?.hasPendingChanges != after?.hasPendingChanges {
            await onAccountDataChanged()
        }
    }

    private func runOwned(accountID: UUID) async throws {
        var failure: (any Error)?
        var boardFailures: [SyncScope: any Error] = [:]
        var threadFailures: [EntityID: any Error] = [:]
        while true {
            try Task.checkCancellation()
            guard let account = try await accountStore.fetchAccounts().first(where: { $0.id == accountID }) else {
                throw VikunjaError.notFound
            }
            let engine = makeEngine(account)
            try await uploadPriorityTasks(accountID: accountID, engine: engine)
            let authenticationRevision = authenticationRefreshes[accountID]
            let needsPass = workByAccount[accountID]?.needsAnotherPass ?? false
            workByAccount[accountID]?.needsAnotherPass = false
            if needsPass {
                do {
                    try await engine.synchronize()
                    acknowledgeAuthenticationRefresh(authenticationRevision, accountID: accountID)
                    failure = nil
                } catch {
                    try checkSyncInterruption(error)
                    failure = error
                }
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
                } catch {
                    try checkSyncInterruption(error)
                    threadFailures[id] = error
                }
                workByAccount[accountID]?.requestedThreads.remove(id)
            }
            boardFailures = await pullPendingBoards(account, previousFailures: boardFailures)
            if hasPendingWork(accountID: accountID) {
                continue
            }
            break
        }
        if let failure = failure ?? threadFailures.values.first {
            throw failure
        }
        if !boardFailures.isEmpty {
            throw BoardRefreshFailures(errors: boardFailures)
        }
    }

    private func uploadPriorityTasks(accountID: UUID, engine: SyncEngine) async throws {
        let taskIDs = workByAccount[accountID]?.priorityUploads ?? []
        workByAccount[accountID]?.priorityUploads = []
        for taskID in taskIDs {
            try Task.checkCancellation()
            try await engine.drainTaskMutations(onlyTaskID: taskID)
        }
    }

    private func hasPendingWork(accountID: UUID) -> Bool {
        guard let work = workByAccount[accountID] else { return false }
        return !work.priorityUploads.isEmpty || !work.pendingBoards.isEmpty
            || work.needsAnotherPass || !work.pendingThreads.isEmpty
    }

    private func acknowledgeAuthenticationRefresh(_ revision: UUID?, accountID: UUID) {
        guard authenticationRefreshes[accountID] == revision else { return }
        authenticationRefreshes[accountID] = nil
    }

    private func pullPendingBoards(
        _ account: InstanceAccount, previousFailures: [SyncScope: any Error],
    ) async -> [SyncScope: any Error] {
        let boards = workByAccount[account.id]?.pendingBoards ?? []
        workByAccount[account.id]?.pendingBoards = []
        var failures = previousFailures
        for scope in boards {
            guard !Task.isCancelled else { break }
            guard case let .kanban(projectID, viewID) = scope else { continue }
            do {
                try await makeEngine(account).refreshKanban(projectID: projectID, viewID: viewID)
                failures[scope] = nil
            } catch { failures[scope] = error }
            workByAccount[account.id]?.requestedBoards.remove(scope)
        }
        return failures
    }

    /// Staging reuses the ordinary pull path, but never drains the live queue.
    public func reloadFromServer(accountID: UUID) async throws {
        try localStore.executionLifecycle?.checkAccess()
        let id = UUID()
        let lifecycle = localStore.executionLifecycle
        let task = Task {
            defer { lifecycle?.untrack(id) }
            try await self.performReloadFromServer(accountID: accountID)
        }
        lifecycle?.track(task, id: id)
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private func performReloadFromServer(accountID: UUID) async throws {
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
        let ownership = SyncOwnership(accountID: accountID)
        try await ownership.acquire(in: localStore)
        do {
            try await replaceOwnedAccount(account)
            await ownership.release(in: localStore)
        } catch {
            await ownership.release(in: localStore)
            throw error
        }
    }

    private func replaceOwnedAccount(_ account: InstanceAccount) async throws {
        let accountID = account.id
        let original = try await localStore.beginAccountReload(accountID: accountID)
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let staging = try LocalStore(directory: directory, executionLifecycle: localStore.executionLifecycle)
            try await staging.write { db in try original.seedIdentities(db: db) }
            try await makeEngine(account, store: staging).downloadReplacement(original: original)
            try Task.checkCancellation()
            let replacement = try await staging.read { db in try AccountSnapshot(accountID: accountID, db: db) }
            try await localStore.replaceAccount(accountID: accountID, with: replacement, expecting: original)
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
            taskBulkUpdateRepository: clientFactory.makeTaskBulkUpdateRepository(
                baseURL: account.baseURL, tokenProvider: resolvedTokenProvider,
            ),
            commentRepository: commentRepository,
            filterRepository: filterRepository,
            userRepository: clientFactory.makeUserRepository(
                baseURL: account.baseURL, tokenProvider: resolvedTokenProvider,
            ),
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
