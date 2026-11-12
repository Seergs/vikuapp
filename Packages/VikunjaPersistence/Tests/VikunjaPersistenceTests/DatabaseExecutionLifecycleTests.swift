import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

/// GRDB suspension notifications are process-wide; managed-store cases must not
/// overlap one another. Other suites use standalone stores and do not subscribe.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct DatabaseExecutionLifecycleTests {
    @Test func `overlapping background windows retain access until the last one closes`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let widgets = lifecycle.beginBackgroundExecution()
        let scheduledSync = lifecycle.beginBackgroundExecution()
        lifecycle.setForeground(false)
        lifecycle.endBackgroundExecution(widgets)
        #expect(!lifecycle.isSuspended)
        try await store.write { db in try db.execute(sql: "CREATE TABLE leaseTest (id INTEGER)") }
        lifecycle.endBackgroundExecution(scheduledSync)
        #expect(lifecycle.isSuspended)
        await #expect(throws: CancellationError.self) {
            try await store.write { db in try db.execute(sql: "INSERT INTO leaseTest VALUES (1)") }
        }
        // A scheduled callback may run while the UI stays in background.
        let next = lifecycle.beginBackgroundExecution()
        #expect(!lifecycle.isSuspended)
        try await store.write { db in try db.execute(sql: "INSERT INTO leaseTest VALUES (2)") }
        lifecycle.endBackgroundExecution(next)
        lifecycle.endBackgroundExecution(next)
        lifecycle.setForeground(true)
        #expect(try await store.read { db in try Int.fetchOne(db, sql: "SELECT id FROM leaseTest") } == 2)
    }

    @Test func `suspension rolls back an open transaction and preserves earlier queued intent`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let accountID = UUID()
        let repository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await repository.create(Project(id: .local(UUID()), title: "Pending before suspension"))
        let before = try await store.pendingSyncOperations(accountID: accountID)
        let started = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let transaction = Task {
            try await store.write { db in
                try db.execute(sql: "UPDATE project SET title = 'Uncommitted'")
                started.continuation.yield()
                release.wait()
                try db.execute(sql: "UPDATE project SET title = 'Must not commit'")
            }
        }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        lifecycle.setForeground(false)
        release.signal()
        await #expect(throws: CancellationError.self) { try await transaction.value }
        // WAL readers remain usable even with writes suspended.
        #expect(try await repository.fetchProjects().map(\.title) == ["Pending before suspension"])
        lifecycle.setForeground(true)
        #expect(try await store.pendingSyncOperations(accountID: accountID) == before)
        _ = try await repository.create(Project(id: .local(UUID()), title: "After resume"))
        #expect(try await repository.fetchProjects().count == 2)
    }

    @Test func `rapid resume does not commit a transaction from an interrupted execution window`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        try await store.write { db in try db.execute(sql: "CREATE TABLE generationTest (id INTEGER)") }
        let started = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let transaction = Task {
            try await store.write { db in
                try db.execute(sql: "INSERT INTO generationTest VALUES (1)")
                started.continuation.yield()
                release.wait()
            }
        }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        lifecycle.setForeground(false)
        lifecycle.setForeground(true)
        release.signal()
        await #expect(throws: CancellationError.self) { try await transaction.value }
        #expect(try await store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM generationTest") } == 0)
    }

    @Test func `observers opened while suspended emit fresh values after resume and subsequent writes`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let accountID = UUID()
        let repository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        lifecycle.setForeground(false)
        let changes = await store.observeChanges(accountID: accountID)
        let statuses = await store.observePendingSyncStatuses(accountID: accountID)
        let operations = await store.observePendingSyncOperations(accountID: accountID)
        var changeEvents = changes.makeAsyncIterator()
        var statusEvents = statuses.makeAsyncIterator()
        var operationEvents = operations.makeAsyncIterator()
        lifecycle.setForeground(true)
        #expect(try await changeEvents.next() != nil)
        #expect(try await statusEvents.next()?.isEmpty == true)
        #expect(try await operationEvents.next()?.isEmpty == true)
        lifecycle.setForeground(false)
        lifecycle.setForeground(true)
        _ = try await repository.create(Project(id: .local(UUID()), title: "Observed after resume"))
        #expect(try await changeEvents.next() != nil)
        #expect(try await statusEvents.next()?.count == 1)
        #expect(try await operationEvents.next()?.count == 1)
    }

    @Test func `a cancelled observer waiting for resume finishes without needing foreground`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        lifecycle.setForeground(false)
        let observer = Task {
            for try await _ in await store.observeChanges(accountID: UUID()) {}
        }
        observer.cancel()
        _ = await observer.result
        #expect(lifecycle.isSuspended)
    }

    @Test func `expiration cancels actual workers and resume starts a fresh sync without false failures`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let accounts = FakeAccountStore()
        let account = try InstanceAccount(
            displayName: "Test", baseURL: #require(URL(string: "https://lifecycle.example.com")),
        )
        try await accounts.addAccount(account, token: "token")
        let factory = FakeInstanceClientFactory()
        let remote = factory.projectRepository(for: account.baseURL)
        let started = AsyncStream<Void>.makeStream()
        remote.beforeFetchResponse = {
            started.continuation.yield()
            // Cancellation ends an AsyncStream iterator, so only cancelling the
            // coordinator's actual worker can release this request.
            let blocked = AsyncStream<Void> { _ in }
            for await _ in blocked {}
        }
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: LifecycleReachability(), tokenProvider: { _ in { "token" } },
        )
        let repository = OfflineProjectRepository(
            localStore: store, accountID: account.id, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await repository.create(Project(id: .local(UUID()), title: "Keep this intent"))
        let window = lifecycle.beginBackgroundExecution()
        lifecycle.setForeground(false)
        let sync = Task { try await coordinator.refresh(accountID: account.id, scope: .account) }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        lifecycle.endBackgroundExecution(window)
        await #expect(throws: CancellationError.self) { try await sync.value }
        // No authorized window: triggers must not start another network request.
        await coordinator.syncAllAccounts()
        await coordinator.requestSync(accountID: account.id)
        #expect(remote.fetchProjectsCallCount == 1)
        let pending = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(pending.count == 1)
        #expect(pending.first?.retryCount == 0)
        #expect(pending.first?.lastError == nil)
        remote.beforeFetchResponse = nil
        lifecycle.setForeground(true)
        try await coordinator.refresh(accountID: account.id, scope: .account)
        #expect(remote.fetchProjectsCallCount == 2)
        #expect(try await store.pendingSyncOperations(accountID: account.id).isEmpty)
        #expect(try await repository.fetchProjects().map(\.title) == ["Keep this intent"])
    }

    @Test func `an interrupted observation restarts after resume while unrelated errors still propagate`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let attempts = ObservationAttempts()
        let interrupted = AsyncStream<Void>.makeStream()
        let stream: AsyncThrowingStream<Int, Error> = store.recoveringObservation { continuation in
            if await attempts.next() == 1 {
                lifecycle.setForeground(false)
                interrupted.continuation.yield()
                throw DatabaseError(resultCode: .SQLITE_INTERRUPT)
            }
            continuation.yield(42)
        }
        var interruptions = interrupted.stream.makeAsyncIterator()
        _ = await interruptions.next()
        lifecycle.setForeground(true)
        var values = stream.makeAsyncIterator()
        #expect(try await values.next() == 42)
        #expect(await attempts.count == 2)
        let failed: AsyncThrowingStream<Int, Error> = store.recoveringObservation { _ in
            throw DatabaseError(resultCode: .SQLITE_ABORT)
        }
        var failures = failed.makeAsyncIterator()
        await #expect(throws: DatabaseError.self) { _ = try await failures.next() }
    }

    @Test func `bulk claims interrupted by suspension recover without increasing failure counts`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let accountID = UUID()
        let projects = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await projects.create(Project(id: .local(UUID()), title: "Work"))
        let remoteProjects = FakeProjectRepository()
        let remoteTasks = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: remoteProjects, labelRepository: FakeLabelRepository(),
            taskRepository: remoteTasks, relationRepository: FakeTaskRelationRepository(),
            taskBulkUpdateRepository: remoteTasks, accountID: accountID,
        )
        try await engine.drainProjectMutations()
        let project = try #require(try await projects.fetchProjects().first)
        let tasks = OfflineTaskRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        for title in ["First", "Second"] {
            _ = try await tasks.create(VikunjaTask(id: .local(UUID()), title: title, projectID: project.id))
        }
        try await engine.drainTaskMutations()
        let ids = try await tasks.fetchTasks(projectID: project.id).map(\.id)
        _ = try await tasks.setCompletion(taskIDs: ids, isDone: true)
        remoteTasks.fetchTaskResponse = { _ in
            lifecycle.setForeground(false)
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) { try await engine.drainTaskMutations() }
        let interrupted = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(interrupted.count == 2)
        #expect(interrupted.allSatisfy { $0.status == .inFlight && $0.retryCount == 0 && $0.lastError == nil })
        #expect(try await tasks.fetchTasks(projectID: project.id).allSatisfy(\.isDone))
        remoteTasks.fetchTaskResponse = nil
        lifecycle.setForeground(true)
        try await engine.drainTaskMutations()
        #expect(try await store.pendingSyncOperations(accountID: accountID).isEmpty)
        #expect(try await tasks.fetchTasks(projectID: project.id).allSatisfy(\.isDone))
    }

    @Test func `resuming a cancelled slow account neither blocks local saves nor a healthy account`() async throws {
        let lifecycle = DatabaseExecutionLifecycle()
        defer { lifecycle.setForeground(true) }
        let store = try makeStore(lifecycle)
        let accounts = FakeAccountStore()
        let first = try InstanceAccount(displayName: "Slow", baseURL: #require(URL(string: "https://slow.example.com")))
        let second = try InstanceAccount(displayName: "Fast", baseURL: #require(URL(string: "https://fast.example.com")))
        try await accounts.addAccount(first, token: "token")
        try await accounts.addAccount(second, token: "token")
        let factory = FakeInstanceClientFactory()
        let slow = factory.projectRepository(for: first.baseURL)
        let fast = factory.projectRepository(for: second.baseURL)
        let request = UncancellableRequest()
        let started = AsyncStream<Void>.makeStream()
        slow.beforeFetchResponse = { await request.wait(signal: started.continuation) }
        let coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory,
            reachability: LifecycleReachability(), tokenProvider: { _ in { "token" } },
        )
        let original = Task { try await coordinator.refresh(accountID: first.id, scope: .account) }
        var starts = started.stream.makeAsyncIterator()
        _ = await starts.next()
        lifecycle.setForeground(false)
        lifecycle.setForeground(true)
        let healthyStarted = AsyncStream<Void>.makeStream()
        fast.beforeFetchResponse = { healthyStarted.continuation.yield() }
        let resumed = Task { await coordinator.syncAllAccounts() }
        var healthyEvents = healthyStarted.stream.makeAsyncIterator()
        #expect(await healthyEvents.next() != nil)
        let sync = AccountSync(accountID: first.id, coordinator: coordinator, localStore: store)
        let repository = OfflineProjectRepository(localStore: store, accountID: first.id, syncRequester: sync)
        _ = try await repository.create(Project(id: .local(UUID()), title: "Saved during cancellation"))
        #expect(slow.createdProjects.isEmpty)
        #expect(try await repository.fetchProjects().map(\.title) == ["Saved during cancellation"])
        slow.beforeFetchResponse = nil
        await request.release()
        await #expect(throws: CancellationError.self) { try await original.value }
        await resumed.value
        try await coordinator.refresh(accountID: first.id, scope: .account)
        #expect(slow.createdProjects.count == 1)
        #expect(try await store.pendingSyncOperations(accountID: first.id).isEmpty)
    }

    private func makeStore(_ lifecycle: DatabaseExecutionLifecycle) throws -> LocalStore {
        try LocalStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            executionLifecycle: lifecycle,
        )
    }
}

private actor LifecycleReachability: ReachabilityMonitoring {
    var isReachable: Bool {
        true
    }

    func reachabilityRegained() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

private actor ObservationAttempts {
    private(set) var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

/// Models a dependency that needs time to unwind even after its task is cancelled.
private actor UncancellableRequest {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(signal: AsyncStream<Void>.Continuation) async {
        await withCheckedContinuation {
            continuation = $0
            signal.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
