import Foundation
import GRDB
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct AccountReloadTests {
    private struct Fixture {
        let store: LocalStore
        let factory = FakeInstanceClientFactory()
        let reachability = CoordinatorReachabilityMonitor()
        let accounts = FakeAccountStore()
        let account: InstanceAccount
        let coordinator: SyncCoordinator
        let tasks: OfflineTaskRepository

        init() async throws {
            self.store = try LocalStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            )
            self.account = try InstanceAccount(
                displayName: "Reload", baseURL: #require(URL(string: "https://reload.example.com")),
            )
            try await accounts.addAccount(account, token: "token")
            factory.projectRepository(for: account.baseURL).projects = [
                Project(id: .remote(1), title: "Server project"),
            ]
            factory.taskRepository(for: account.baseURL).tasks = [
                VikunjaTask(id: .remote(1), title: "Server task", projectID: .remote(1)),
                VikunjaTask(id: .remote(2), title: "Deleted locally", projectID: .remote(1)),
            ]
            self.coordinator = SyncCoordinator(
                localStore: store, accountStore: accounts, clientFactory: factory,
                reachability: reachability, tokenProvider: { _ in { "token" } },
            )
            self.tasks = OfflineTaskRepository(
                localStore: store, accountID: account.id, syncRequester: NoopKanbanSyncRequester(),
            )
            try await coordinator.refresh(accountID: account.id, scope: .account)
            var edited = try await tasks.fetchTask(id: .remote(1))
            edited.title = "Local edit"
            _ = try await tasks.update(edited)
            try await tasks.delete(id: .remote(2))
            _ = try await tasks.create(VikunjaTask(id: .local(UUID()), title: "Only local", projectID: .remote(1)))
            let accountID = account.id
            try await store.write { db in
                try db.execute(sql: """
                UPDATE mutationQueueItem SET status = 'failed', retryCount = 4, lastError = 'rejected'
                WHERE accountID = ?
                """, arguments: [accountID])
            }
        }

        func snapshot() async throws -> AccountSnapshot {
            let id = account.id
            return try await store.read { db in try AccountSnapshot(accountID: id, db: db) }
        }
    }

    @Test func `successful reload restores server truth without uploading pending changes`() async throws {
        let fixture = try await Fixture()
        let projects = OfflineProjectRepository(
            localStore: fixture.store, accountID: fixture.account.id, syncRequester: NoopKanbanSyncRequester(),
        )
        let localProject = try await projects.create(Project(id: .local(UUID()), title: "Only local project"))
        _ = try await fixture.tasks.create(
            VikunjaTask(id: .local(UUID()), title: "Dependent local task", projectID: localProject.id),
        )
        let before = try await fixture.snapshot()
        try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        let after = try await fixture.snapshot()
        #expect(after.mutations.isEmpty)
        #expect(after.projects.map(\.title) == ["Server project"])
        #expect(after.tasks.map(\.title).sorted() == ["Deleted locally", "Server task"])
        #expect(after.tasks.first { $0.remoteID == 1 }?.localID == before.tasks.first { $0.remoteID == 1 }?.localID)
        let remote = fixture.factory.taskRepository(for: fixture.account.baseURL)
        #expect(remote.createdTasks.isEmpty)
        #expect(remote.updatedTasks.isEmpty)
        #expect(remote.deletedIDs.isEmpty)
    }

    @Test func `a partial download failure preserves the complete cache and queue and allows retry`() async throws {
        let fixture = try await Fixture()
        let before = try await fixture.snapshot()
        fixture.factory.projectRepository(for: fixture.account.baseURL).projects.append(
            Project(id: .remote(2), title: "New server project"),
        )
        let remote = fixture.factory.taskRepository(for: fixture.account.baseURL)
        remote.fetchErrorsByProjectID[2] = VikunjaError.timeout
        await #expect(throws: VikunjaError.timeout) {
            try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        }
        #expect(try await fixture.snapshot() == before)
        remote.fetchErrorsByProjectID = [:]
        try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        #expect(try await fixture.snapshot().mutations.isEmpty)
    }

    @Test func `offline reload preserves local data`() async throws {
        let fixture = try await Fixture()
        let before = try await fixture.snapshot()
        await fixture.reachability.setReachable(false)
        await #expect(throws: VikunjaError.offline) {
            try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        }
        #expect(try await fixture.snapshot() == before)
    }

    @Test func `a slow reload keeps reads available blocks writes and duplicate reloads and supports cancellation`() async throws {
        let fixture = try await Fixture()
        let before = try await fixture.snapshot()
        let (entered, didEnter) = AsyncStream<Void>.makeStream()
        let (release, allowResponse) = AsyncStream<Void>.makeStream()
        defer { allowResponse.finish() }
        fixture.factory.projectRepository(for: fixture.account.baseURL).beforeFetchResponse = {
            didEnter.yield(())
            didEnter.finish()
            for await _ in release {}
        }
        let reload = Task { try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id) }
        for await _ in entered {}
        #expect(try await fixture.snapshot() == before)
        await #expect(throws: LocalStoreError.self) {
            _ = try await fixture.tasks.create(VikunjaTask(id: .local(UUID()), title: "Blocked", projectID: .remote(1)))
        }
        await #expect(throws: LocalStoreError.self) {
            try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        }
        await #expect(throws: LocalStoreError.self) {
            try await fixture.coordinator.refresh(accountID: fixture.account.id, scope: .account)
        }
        await fixture.coordinator.requestSync(accountID: fixture.account.id)
        reload.cancel()
        allowResponse.finish()
        await #expect(throws: CancellationError.self) { try await reload.value }
        #expect(try await fixture.snapshot() == before)
        _ = try await fixture.tasks.create(
            VikunjaTask(id: .local(UUID()), title: "Allowed again", projectID: .remote(1)),
        )
    }

    @Test func `another account can sync and edit while this account is reloading`() async throws {
        let fixture = try await Fixture()
        let other = try InstanceAccount(displayName: "Other", baseURL: #require(URL(string: "https://other.example.com")))
        try await fixture.accounts.addAccount(other, token: "other")
        let otherRemote = fixture.factory.projectRepository(for: other.baseURL)
        otherRemote.projects = [Project(id: .remote(1), title: "Other project")]
        let (entered, didEnter) = AsyncStream<Void>.makeStream()
        let (release, allowResponse) = AsyncStream<Void>.makeStream()
        defer { allowResponse.finish() }
        fixture.factory.projectRepository(for: fixture.account.baseURL).beforeFetchResponse = {
            didEnter.yield(())
            didEnter.finish()
            for await _ in release {}
        }
        let reload = Task { try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id) }
        for await _ in entered {}
        await fixture.coordinator.syncAllAccounts()
        let otherProjects = OfflineProjectRepository(
            localStore: fixture.store, accountID: other.id, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await otherProjects.create(Project(id: .local(UUID()), title: "Other local project"))
        let otherBefore = try await fixture.store.read { db in try AccountSnapshot(accountID: other.id, db: db) }
        allowResponse.finish()
        try await reload.value
        let otherAfter = try await fixture.store.read { db in try AccountSnapshot(accountID: other.id, db: db) }
        #expect(otherAfter == otherBefore)
        #expect(otherAfter.projects.count == 2)
        #expect(otherAfter.mutations.count == 1)
    }

    @Test func `reload restores a locally deleted comment and cached boards only after all downloads succeed`() async throws {
        let fixture = try await Fixture()
        let remoteComments = fixture.factory.commentRepository(for: fixture.account.baseURL)
        remoteComments.comments = [TaskComment(
            id: .remote(10), comment: "Server comment", author: User(id: 1, username: "owner"),
            created: Date(), updated: Date(),
        )]
        try await fixture.coordinator.refresh(accountID: fixture.account.id, scope: .comments(.remote(1)))
        let comments = OfflineTaskCommentRepository(
            localStore: fixture.store, accountID: fixture.account.id, syncRequester: NoopKanbanSyncRequester(),
        )
        try await comments.deleteComment(.remote(10), fromTask: .remote(1))
        let engine = SyncEngine(
            localStore: fixture.store, projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(), accountID: fixture.account.id,
            bucketRepository: fixture.factory.boardRepository, capabilityProvider: KanbanCapabilities(),
        )
        try await engine.pullKanban(projectID: .remote(1))
        let before = try await fixture.snapshot()
        #expect(before.comments.isEmpty)
        #expect(before.kanbanViews.count == 1)
        await fixture.factory.boardRepository.fail()
        await #expect(throws: VikunjaError.offline) {
            try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        }
        #expect(try await fixture.snapshot() == before)
        await fixture.factory.boardRepository.set(KanbanDownload(
            viewID: 10, mode: "manual", filterQuery: "", defaultBucketID: nil, doneBucketID: nil, buckets: [],
        ))
        try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        let after = try await fixture.snapshot()
        #expect(after.comments.map(\.comment) == ["Server comment"])
        #expect(after.kanbanViews.count == 1)
        #expect(after.kanbanViews.first?.lastCompletePullAt != nil)
        #expect(after.mutations.isEmpty)
    }

    @Test func `reload cancels an existing sync before it can upload the queue`() async throws {
        let fixture = try await Fixture()
        let (entered, didEnter) = AsyncStream<Void>.makeStream()
        let (release, allowResponse) = AsyncStream<Void>.makeStream()
        defer { allowResponse.finish() }
        let remote = fixture.factory.projectRepository(for: fixture.account.baseURL)
        remote.beforeFetchResponse = {
            didEnter.yield(())
            didEnter.finish()
            for await _ in release {}
        }
        let sync = Task { try await fixture.coordinator.refresh(accountID: fixture.account.id, scope: .account) }
        for await _ in entered {}
        // Cancelled AsyncStream iteration returns immediately; the replacement fetch
        // can then use the same stream, which cancellation has already terminated.
        try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        _ = try? await sync.value
        #expect(try await fixture.snapshot().mutations.isEmpty)
        let remoteTasks = fixture.factory.taskRepository(for: fixture.account.baseURL)
        #expect(remoteTasks.createdTasks.isEmpty)
        #expect(remoteTasks.updatedTasks.isEmpty)
        #expect(remoteTasks.deletedIDs.isEmpty)
    }

    @Test func `database failure during replacement rolls back deletes and preserves pending work`() async throws {
        let fixture = try await Fixture()
        let before = try await fixture.snapshot()
        try await fixture.store.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_reload BEFORE INSERT ON task
            WHEN NEW.title = 'Server task'
            BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;
            """)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        }
        #expect(try await fixture.snapshot() == before)
        try await fixture.store.write { db in try db.execute(sql: "DROP TRIGGER reject_reload") }
        try await fixture.coordinator.reloadFromServer(accountID: fixture.account.id)
        #expect(try await fixture.snapshot().mutations.isEmpty)
    }
}
