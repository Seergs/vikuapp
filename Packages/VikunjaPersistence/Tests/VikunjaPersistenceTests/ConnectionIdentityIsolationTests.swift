import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

/// Rejected connection changes preserve account-scoped cached data and queued intent.
@Suite(.timeLimit(.minutes(1)))
struct ConnectionIdentityIsolationTests {
    enum Mutation: Sendable, CaseIterable { case create, edit, delete }

    @Test(arguments: Mutation.allCases)
    func `rejected server change preserves intent and synchronizes only to the source`(_ mutation: Mutation) async throws {
        let fixture = try IdentityFixture()
        defer { fixture.removeStore() }
        try await fixture.prepare()
        await fixture.reachability.setReachable(false)
        switch mutation {
        case .create:
            _ = try await fixture.localTasks.create(VikunjaTask(id: .local(UUID()), title: "Queued on A", projectID: 1))
        case .edit:
            var task = try await fixture.localTasks.fetchTask(id: 1)
            task.title = "Queued on A"
            _ = try await fixture.localTasks.update(task)
        case .delete: try await fixture.localTasks.delete(id: 1)
        }
        let before = try await fixture.store.pendingSyncOperations(accountID: fixture.account.id)
        await #expect(throws: ConnectionIdentityError.serverChanged) { try await fixture.changeServer() }
        #expect(try await fixture.accounts.activeAccount() == fixture.account)
        #expect(try await fixture.accounts.token(forAccountID: fixture.account.id) == "source")
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.account.id) == before)
        await fixture.reachability.setReachable(true)
        try await fixture.sync.refresh(scope: .account)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.account.id).isEmpty)
        #expect(fixture.target.createdTasks.isEmpty)
        #expect(fixture.target.updatedTasks.isEmpty)
        #expect(fixture.target.deletedIDs.isEmpty)
        #expect(fixture.target.tasks.first?.title == "Original")
        switch mutation {
        case .create: #expect(fixture.source.createdTasks.map(\.title) == ["Queued on A"])
        case .edit: #expect(fixture.source.updatedTasks.map(\.title) == ["Queued on A"])
        case .delete: #expect(fixture.source.deletedIDs == [1])
        }
    }

    @Test
    func `empty queue does not allow reassignment of cached data`() async throws {
        let fixture = try IdentityFixture()
        defer { fixture.removeStore() }
        try await fixture.prepare()
        await #expect(throws: ConnectionIdentityError.serverChanged) { try await fixture.changeServer() }
        #expect(try await fixture.accounts.activeAccount()?.baseURL == fixture.account.baseURL)
        #expect(try await fixture.localTasks.fetchTask(id: 1).title == "Original")
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.account.id).isEmpty)
    }

    @Test
    func `late source response remains under the source identity after a rejected switch`() async throws {
        let fixture = try IdentityFixture()
        defer { fixture.removeStore() }
        try await fixture.prepare()
        let gate = IdentityResponseGate()
        fixture.factory.projectRepository(for: fixture.account.baseURL).beforeFetchResponse = { await gate.pause() }
        fixture.source.tasks[0].title = "Late source response"
        var starts = gate.started.makeAsyncIterator()
        let pass = Task { try await fixture.sync.refresh(scope: .account) }
        _ = await starts.next()
        await #expect(throws: ConnectionIdentityError.serverChanged) { try await fixture.changeServer() }
        await gate.release()
        try await pass.value
        #expect(try await fixture.accounts.activeAccount()?.baseURL == fixture.account.baseURL)
        #expect(try await fixture.localTasks.fetchTask(id: 1).title == "Late source response")
        #expect(fixture.target.fetchTasksCallCount == 0)
    }
}

private actor IdentityResponseGate {
    nonisolated let started: AsyncStream<Void>
    private let start: AsyncStream<Void>.Continuation
    private let response = AsyncStream<Void>.makeStream()
    init() {
        (self.started, self.start) = AsyncStream<Void>.makeStream()
    }

    func pause() async {
        start.yield(); for await _ in response.stream {}
    }

    func release() {
        response.continuation.finish()
    }
}

private struct IdentityFixture {
    let directory: URL
    let store: LocalStore
    let accounts = FakeAccountStore()
    let factory = FakeInstanceClientFactory()
    let reachability = CoordinatorReachabilityMonitor()
    let account = InstanceAccount(displayName: "Source", baseURL: URL(string: "https://source.example.com")!)
    let targetURL = URL(string: "https://target.example.com")!
    let coordinator: SyncCoordinator

    var source: FakeTaskRepository {
        factory.taskRepository(for: account.baseURL)
    }

    var target: FakeTaskRepository {
        factory.taskRepository(for: targetURL)
    }

    var sync: AccountSync {
        AccountSync(accountID: account.id, coordinator: coordinator, localStore: store)
    }

    var localTasks: OfflineTaskRepository {
        OfflineTaskRepository(localStore: store, accountID: account.id, syncRequester: sync)
    }

    init() throws {
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.store = try LocalStore(directory: directory)
        self.coordinator = SyncCoordinator(
            localStore: store, accountStore: accounts, clientFactory: factory, reachability: reachability,
            tokenProvider: { _ in { "test-credential" } },
        )
        for url in [account.baseURL, targetURL] {
            factory.projectRepository(for: url).projects = [Project(id: 1, title: "Project")]
            factory.taskRepository(for: url).tasks = [
                VikunjaTask(id: 1, title: "Original", projectID: 1, updated: Date(timeIntervalSince1970: 1000)),
            ]
        }
    }

    func prepare() async throws {
        try await accounts.addAccount(account, token: "source")
        try await sync.prepare()
    }

    func changeServer() async throws {
        var changed = account
        changed.baseURL = targetURL
        try await accounts.updateAccount(changed, token: "target")
        await coordinator.credentialsDidChange(accountID: account.id)
    }

    func removeStore() {
        try? FileManager.default.removeItem(at: directory)
    }
}
