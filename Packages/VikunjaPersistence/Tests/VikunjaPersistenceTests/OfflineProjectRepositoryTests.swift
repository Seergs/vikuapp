import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor FakeReachabilityMonitor: ReachabilityMonitoring {
    var isReachable: Bool

    init(isReachable: Bool) {
        self.isReachable = isReachable
    }

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func setReachable(_ value: Bool) {
        isReachable = value
    }
}

struct OfflineProjectRepositoryTests {
    private struct Fixture {
        let repository: OfflineProjectRepository
        let store: LocalStore
        let network: FakeProjectRepository
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeRepository(
        online: Bool,
        accountID: UUID = UUID(),
        network: FakeProjectRepository = FakeProjectRepository(),
    ) throws -> Fixture {
        let store = try LocalStore(directory: temporaryDirectory())
        let engine = SyncEngine(
            localStore: store, projectRepository: network,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(), accountID: accountID,
        )
        let reachability = FakeReachabilityMonitor(isReachable: online)
        let repository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncEngine: engine, reachability: reachability,
        )
        return Fixture(repository: repository, store: store, network: network)
    }

    @Test
    func `fetchProjects is empty for a freshly created local store`() async throws {
        let fixture = try makeRepository(online: false)
        #expect(try await fixture.repository.fetchProjects().isEmpty)
    }

    @Test
    func `fetchProjects pulls once on a cold, never-synced account instead of racing a background sync`() async throws {
        let network = FakeProjectRepository()
        network.projects = [Project(id: 1, title: "Already on the server")]
        let fixture = try makeRepository(online: true, network: network)

        let projects = try await fixture.repository.fetchProjects()

        #expect(projects.map(\.title) == ["Already on the server"])
        #expect(network.fetchProjectsCallCount == 1)

        // A second read doesn't pull again - `SyncStateRecord` now says this
        // account has already synced once.
        _ = try await fixture.repository.fetchProjects()
        #expect(network.fetchProjectsCallCount == 1)
    }

    @Test
    func `fetchProjects never pulls while offline on a cold, never-synced account`() async throws {
        let fixture = try makeRepository(online: false)

        #expect(try await fixture.repository.fetchProjects().isEmpty)
        #expect(fixture.network.fetchProjectsCallCount == 0)
    }

    @Test
    func `create on a cold never-synced account is not undone by its own cold-start pull`() async throws {
        // Regression test: `create`/`update` used to read back the row they
        // just wrote through the public `fetchProject(id:)`, which (for a
        // never-synced account) triggered a reconciling pull of its own -
        // and since the fake server here doesn't echo back what `create`
        // just pushed, that pull would delete the row before this method
        // ever got to return it.
        let fixture = try makeRepository(online: true)

        let created = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        #expect(created.title == "Groceries")
        #expect(created.id.remoteValue != nil)
        let projects = try await fixture.repository.fetchProjects()
        #expect(projects.map(\.title) == ["Groceries"])
    }

    @Test
    func `create while offline returns a local id and leaves the mutation queued`() async throws {
        let fixture = try makeRepository(online: false)

        let created = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        guard case .local = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        #expect(created.title == "Groceries")
        #expect(fixture.network.createdProjects.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(queued[0].status == .pending)
    }

    @Test
    func `create while online drains immediately and returns the servers remote id`() async throws {
        let fixture = try makeRepository(online: true)

        let created = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        #expect(created.id.remoteValue != nil)
        #expect(fixture.network.createdProjects.map(\.title) == ["Groceries"])
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `fetchProjects reflects a project created offline`() async throws {
        let fixture = try makeRepository(online: false)
        _ = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        let projects = try await fixture.repository.fetchProjects()

        #expect(projects.map(\.title) == ["Groceries"])
    }

    @Test
    func `fetchProject throws notFound for an id that was never created`() async throws {
        let fixture = try makeRepository(online: false)
        await #expect(throws: VikunjaError.self) {
            try await fixture.repository.fetchProject(id: .remote(999))
        }
    }

    @Test
    func `updating a project that never synced coalesces into its still pending create`() async throws {
        let fixture = try makeRepository(online: false)
        let created = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        let updated = try await fixture.repository.update(Project(id: created.id, title: "Groceries & Snacks"))

        #expect(updated.title == "Groceries & Snacks")
        guard case .local = updated.id else {
            Issue.record("expected the id to still be local, got \(updated.id)")
            return
        }
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(fixture.network.createdProjects.isEmpty)
    }

    @Test
    func `editing a synced project twice while offline coalesces into one queued update`() async throws {
        let accountID = UUID()
        let network = FakeProjectRepository()
        let store = try LocalStore(directory: temporaryDirectory())
        let onlineEngine = SyncEngine(
            localStore: store, projectRepository: network,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(), accountID: accountID,
        )
        let onlineRepository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncEngine: onlineEngine,
            reachability: FakeReachabilityMonitor(isReachable: true),
        )
        let created = try await onlineRepository.create(Project(id: .local(UUID()), title: "Groceries"))
        #expect(created.id.remoteValue != nil)

        let offlineEngine = SyncEngine(
            localStore: store, projectRepository: network,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(), accountID: accountID,
        )
        let offlineRepository = OfflineProjectRepository(
            localStore: store, accountID: accountID, syncEngine: offlineEngine,
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        _ = try await offlineRepository.update(Project(id: created.id, title: "Groceries v2"))
        let updated = try await offlineRepository.update(Project(id: created.id, title: "Groceries v3"))

        #expect(updated.title == "Groceries v3")
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .update)
    }

    @Test
    func `deleting a project that never synced removes it and its pending create`() async throws {
        let fixture = try makeRepository(online: false)
        let created = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        try await fixture.repository.delete(id: created.id)

        #expect(try await fixture.repository.fetchProjects().isEmpty)
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `deleting a synced project while offline hides it immediately but keeps it queued`() async throws {
        let accountID = UUID()
        let network = FakeProjectRepository()
        let store = try LocalStore(directory: temporaryDirectory())
        let onlineRepository = OfflineProjectRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: network,
                labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: true),
        )
        let created = try await onlineRepository.create(Project(id: .local(UUID()), title: "Groceries"))

        let offlineRepository = OfflineProjectRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: network,
                labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        try await offlineRepository.delete(id: created.id)

        #expect(try await offlineRepository.fetchProjects().isEmpty)
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.count == 1) // still present until the drain actually confirms the delete
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .delete)
    }

    @Test
    func `deleting a synced project while online drains and truly removes the row`() async throws {
        let fixture = try makeRepository(online: true)
        let created = try await fixture.repository.create(Project(id: .local(UUID()), title: "Groceries"))

        try await fixture.repository.delete(id: created.id)

        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `a child created offline under an already pushed parent resolves the real parent id once online`() async throws {
        let fixture = try makeRepository(online: true)
        let parent = try await fixture.repository.create(Project(id: .local(UUID()), title: "Work"))
        let parentRemoteID = try #require(parent.id.remoteValue)

        let child = try await fixture.repository.create(
            Project(id: .local(UUID()), title: "Reports", parentProjectID: parent.id),
        )

        #expect(child.parentProjectID == .remote(parentRemoteID))
        #expect(fixture.network.createdProjects.last?.parentProjectID == .remote(parentRemoteID))
    }

    @Test
    func `fetchProjects never returns another accounts rows`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountA = UUID()
        let accountB = UUID()
        let networkA = FakeProjectRepository()
        let networkB = FakeProjectRepository()
        let repositoryA = OfflineProjectRepository(
            localStore: store, accountID: accountA,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: networkA,
                labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
                relationRepository: FakeTaskRelationRepository(), accountID: accountA,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        let repositoryB = OfflineProjectRepository(
            localStore: store, accountID: accountB,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: networkB,
                labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
                relationRepository: FakeTaskRelationRepository(), accountID: accountB,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )

        _ = try await repositoryA.create(Project(id: .local(UUID()), title: "A's project"))
        _ = try await repositoryB.create(Project(id: .local(UUID()), title: "B's project"))

        #expect(try await repositoryA.fetchProjects().map(\.title) == ["A's project"])
        #expect(try await repositoryB.fetchProjects().map(\.title) == ["B's project"])
    }
}
