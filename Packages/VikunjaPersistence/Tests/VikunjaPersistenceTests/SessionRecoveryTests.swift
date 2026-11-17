import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct SessionRecoveryTests {
    @Test(arguments: [false, true])
    func `recovery refreshes previously synced cache and retains it on failure`(hasCachedTask: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.removeStore() }
        try await fixture.accounts.addAccount(fixture.account, token: "old")
        fixture.projects.projects = [Project(id: 1, title: "Work")]
        fixture.tasks.tasks = hasCachedTask ? [VikunjaTask(id: 1, title: "Cached", projectID: 1)] : []
        try await fixture.sync.prepare()
        await fixture.reachability.setReachable(false)
        var updated = fixture.account
        updated.needsReauthentication = false
        try await fixture.accounts.updateAccount(updated, token: "new-login")
        fixture.tasks.tasks = [VikunjaTask(id: 2, title: "Fresh", projectID: 1)]
        await fixture.coordinator.credentialsDidChange(accountID: updated.id)
        #expect(try await !fixture.sync.hasInitialSnapshot())
        await #expect(throws: VikunjaError.offline) { try await fixture.sync.prepare() }
        #expect(try await fixture.localTasks.fetchTasks(projectID: 1).count == (hasCachedTask ? 1 : 0))
        await fixture.reachability.setReachable(true)
        fixture.projects.fetchError = VikunjaError.network("Unavailable")
        await #expect(throws: (any Error).self) { try await fixture.sync.prepare() }
        #expect(try await !fixture.sync.hasInitialSnapshot())
        #expect(try await fixture.localProjects.fetchProjects().map(\.title) == ["Work"])
        fixture.projects.fetchError = nil
        try await fixture.sync.prepare()
        #expect(try await fixture.sync.hasInitialSnapshot())
        #expect(try await fixture.localTasks.fetchTasks(projectID: 1).map(\.title) == ["Fresh"])
    }

    @Test(arguments: [false, true])
    func `recovery waits for old work then uses updated account`(cancelCaller: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.removeStore() }
        var flagged = fixture.account
        flagged.needsReauthentication = true
        try await fixture.accounts.addAccount(flagged, token: "old")
        fixture.projects.projects = [Project(id: 1, title: "Work")]
        fixture.tasks.tasks = [VikunjaTask(id: 2, title: "Fresh", projectID: 1)]
        let gate = RecoveryPassGate()
        fixture.projects.beforeFetchResponse = { await gate.waitForPass() }
        var starts = gate.starts.makeAsyncIterator()
        let original = Task { try await fixture.sync.refresh(scope: .account) }
        #expect(await starts.next() == 1)
        try await fixture.accounts.updateAccount(fixture.account, token: "new-login")
        await fixture.coordinator.credentialsDidChange(accountID: fixture.account.id)
        if cancelCaller {
            original.cancel()
        }
        await gate.releaseFirst()
        #expect(await starts.next() == 2)
        // Completion of the old pass cannot acknowledge the new credentials.
        #expect(try await !fixture.sync.hasInitialSnapshot())
        let provider = try #require(fixture.factory.tokenProvidersByBaseURL[fixture.account.baseURL])
        #expect(try await provider() == "current-session")
        await gate.releaseSecond()
        if cancelCaller {
            await #expect(throws: CancellationError.self) { try await original.value }
        } else {
            try await original.value
        }
        await fixture.coordinator.waitForCurrentWork()
        #expect(fixture.projects.fetchProjectsCallCount == 2)
        #expect(try await fixture.sync.hasInitialSnapshot())
        #expect(try await fixture.localTasks.fetchTasks(projectID: 1).map(\.title) == ["Fresh"])
    }

    @Test func `recovery keeps conflicting edits recoverable`() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.removeStore() }
        try await fixture.accounts.addAccount(fixture.account, token: "old")
        fixture.projects.projects = [Project(id: 1, title: "Work")]
        let baseline = Date(timeIntervalSince1970: 1000)
        fixture.tasks.tasks = [VikunjaTask(id: 1, title: "Original", projectID: 1, updated: baseline)]
        try await fixture.sync.prepare()
        await fixture.reachability.setReachable(false)
        var task = try await fixture.localTasks.fetchTask(id: 1)
        task.title = "Local edit"
        _ = try await fixture.localTasks.update(task)
        fixture.tasks.tasks[0].title = "Remote edit"
        fixture.tasks.tasks[0].updated = baseline.addingTimeInterval(120)
        try await fixture.accounts.updateAccount(fixture.account, token: "new-login")
        await fixture.coordinator.credentialsDidChange(accountID: fixture.account.id)
        await fixture.reachability.setReachable(true)
        await #expect(throws: (any Error).self) { try await fixture.sync.prepare() }
        let pending = try await fixture.store.pendingSyncOperations(accountID: fixture.account.id)
        #expect(pending.count == 1)
        #expect(pending.first?.needsConflictResolution == true)
        #expect(fixture.tasks.updatedTasks.isEmpty)
        #expect(fixture.tasks.tasks[0].title == "Remote edit")
    }

    @Test func `recovery preserves pending changes offline and uploads on reconnection`() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.removeStore() }
        try await fixture.accounts.addAccount(fixture.account, token: "old")
        fixture.projects.projects = [Project(id: 1, title: "Work")]
        fixture.tasks.tasks = [VikunjaTask(id: 1, title: "Task", projectID: 1, updated: Date())]
        try await fixture.sync.prepare()
        await fixture.reachability.setReachable(false)
        _ = try await fixture.localTasks.setCompletion(taskIDs: [1], isDone: true)
        try await fixture.accounts.updateAccount(fixture.account, token: "new-login")
        await fixture.coordinator.credentialsDidChange(accountID: fixture.account.id)
        await #expect(throws: VikunjaError.offline) { try await fixture.sync.prepare() }
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.account.id).count == 1)
        #expect(try await fixture.localTasks.fetchTasks(projectID: 1).first?.isDone == true)
        await fixture.coordinator.start()
        await fixture.reachability.waitForSubscription()
        await fixture.reachability.setReachable(true)
        // Join the same worker scheduled by connectivity restoration.
        try await fixture.sync.prepare()
        #expect(fixture.tasks.completionCalls.count == 1)
        #expect(fixture.tasks.tasks.first?.isDone == true)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.account.id).isEmpty)
        #expect(try await fixture.sync.hasInitialSnapshot())
        await fixture.reachability.finish()
        await fixture.coordinator.stop()
    }
}

private struct RecoveryFixture {
    let directory: URL
    let store: LocalStore
    let accounts = FakeAccountStore()
    let factory = FakeInstanceClientFactory()
    let reachability = CoordinatorReachabilityMonitor()
    let account = InstanceAccount(displayName: "Recovery", baseURL: URL(string: "https://recovery.example.com")!)
    let coordinator: SyncCoordinator
    var projects: FakeProjectRepository {
        factory.projectRepository(for: account.baseURL)
    }

    var tasks: FakeTaskRepository {
        factory.taskRepository(for: account.baseURL)
    }

    var sync: AccountSync {
        AccountSync(accountID: account.id, coordinator: coordinator, localStore: store)
    }

    var localTasks: OfflineTaskRepository {
        OfflineTaskRepository(localStore: store, accountID: account.id, syncRequester: sync)
    }

    var localProjects: OfflineProjectRepository {
        OfflineProjectRepository(localStore: store, accountID: account.id, syncRequester: sync)
    }

    init() throws {
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.store = try LocalStore(directory: directory)
        self.coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory, reachability: reachability,
            tokenProvider: { account in { account.needsReauthentication ? "expired-session" : "current-session" } },
        )
    }

    func removeStore() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor RecoveryPassGate {
    nonisolated let starts: AsyncStream<Int>
    private let started: AsyncStream<Int>.Continuation
    private let first = AsyncStream<Void>.makeStream()
    private let second = AsyncStream<Void>.makeStream()
    private var pass = 0

    init() {
        (self.starts, self.started) = AsyncStream<Int>.makeStream()
    }

    func waitForPass() async {
        pass += 1
        let current = pass
        started.yield(current)
        let release = current == 1 ? first.stream : second.stream
        for await _ in release {}
    }

    func releaseFirst() {
        first.continuation.finish()
    }

    func releaseSecond() {
        second.continuation.finish()
    }
}
