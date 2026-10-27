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

struct OfflineTaskRepositoryTests {
    private struct Fixture {
        let repository: OfflineTaskRepository
        let store: LocalStore
        let network: FakeTaskRepository
        let accountID: UUID
        /// A project already present locally (as if `pullProjects()` had
        /// already synced it), so `create`/`update`/`fetchTasks` have a real
        /// project to resolve `projectLocalID` against.
        let project: EntityID
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @discardableResult
    private func seedProject(
        in store: LocalStore,
        accountID: UUID,
        remoteID: Int? = 1,
    ) async throws -> ProjectRecord {
        let row = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: remoteID, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        try await store.write { db in try row.insert(db) }
        return row
    }

    private func makeRepository(
        online: Bool,
        accountID: UUID = UUID(),
        network: FakeTaskRepository = FakeTaskRepository(),
    ) async throws -> Fixture {
        let store = try LocalStore(directory: temporaryDirectory())
        let project = try await seedProject(in: store, accountID: accountID)
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(), taskRepository: network, accountID: accountID,
        )
        let reachability = FakeReachabilityMonitor(isReachable: online)
        let repository = OfflineTaskRepository(
            localStore: store, accountID: accountID, syncEngine: engine, reachability: reachability,
        )
        return Fixture(
            repository: repository, store: store, network: network, accountID: accountID,
            project: project.remoteID.map(EntityID.remote) ?? .local(project.localID),
        )
    }

    @Test
    func `fetchTasks is empty for a freshly created local store`() async throws {
        let fixture = try await makeRepository(online: false)
        #expect(try await fixture.repository.fetchTasks(projectID: 1).isEmpty)
    }

    @Test
    func `fetchTasks returns nothing for a project this account has never heard of`() async throws {
        let fixture = try await makeRepository(online: false)
        #expect(try await fixture.repository.fetchTasks(projectID: 999).isEmpty)
    }

    @Test
    func `create on a cold never-synced account is not undone by its own cold-start pull`() async throws {
        // Regression test: mirrors `OfflineProjectRepositoryTests`'s own -
        // `create` must read back the row it just wrote without routing
        // through the public `fetchTask(id:)`'s cold-pull trigger, or a
        // never-synced account's first task would get wiped by a pull that
        // doesn't echo back what `create` just pushed.
        let fixture = try await makeRepository(online: true)

        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        #expect(created.title == "Buy milk")
        #expect(created.id.remoteValue != nil)
        let tasks = try await fixture.repository.fetchTasks(projectID: 1)
        #expect(tasks.map(\.title) == ["Buy milk"])
    }

    @Test
    func `create while offline returns a local id and leaves the mutation queued`() async throws {
        let fixture = try await makeRepository(online: false)

        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        guard case .local = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        #expect(created.title == "Buy milk")
        #expect(fixture.network.createdTasks.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(queued[0].status == .pending)
    }

    @Test
    func `create while online drains immediately and returns the servers remote id`() async throws {
        let fixture = try await makeRepository(online: true)

        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        #expect(created.id.remoteValue != nil)
        #expect(fixture.network.createdTasks.map(\.title) == ["Buy milk"])
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `create under a project that does not exist locally fails rather than inserting a dangling row`() async throws {
        let fixture = try await makeRepository(online: false)
        await #expect(throws: VikunjaError.self) {
            try await fixture.repository.create(
                VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: .remote(999)),
            )
        }
    }

    @Test
    func `fetchTasks reflects a task created offline`() async throws {
        let fixture = try await makeRepository(online: false)
        _ = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        let tasks = try await fixture.repository.fetchTasks(projectID: 1)

        #expect(tasks.map(\.title) == ["Buy milk"])
    }

    @Test
    func `fetchTask throws notFound for an id that was never created`() async throws {
        let fixture = try await makeRepository(online: false)
        await #expect(throws: VikunjaError.self) {
            try await fixture.repository.fetchTask(id: .remote(999))
        }
    }

    @Test
    func `updating a task that never synced coalesces into its still pending create`() async throws {
        let fixture = try await makeRepository(online: false)
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        let updated = try await fixture.repository.update(
            VikunjaTask(id: created.id, title: "Buy milk and eggs", projectID: fixture.project),
        )

        #expect(updated.title == "Buy milk and eggs")
        guard case .local = updated.id else {
            Issue.record("expected the id to still be local, got \(updated.id)")
            return
        }
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(fixture.network.createdTasks.isEmpty)
    }

    @Test
    func `editing a synced task twice while offline coalesces into one queued update`() async throws {
        let accountID = UUID()
        let network = FakeTaskRepository()
        let store = try LocalStore(directory: temporaryDirectory())
        let project = try await seedProject(in: store, accountID: accountID)
        let projectID: EntityID = project.remoteID.map(EntityID.remote) ?? .local(project.localID)
        let onlineRepository = OfflineTaskRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: network, accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: true),
        )
        let created = try await onlineRepository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: projectID),
        )
        #expect(created.id.remoteValue != nil)

        let offlineRepository = OfflineTaskRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: network, accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        _ = try await offlineRepository.update(VikunjaTask(id: created.id, title: "Buy milk v2", projectID: projectID))
        let updated = try await offlineRepository.update(
            VikunjaTask(id: created.id, title: "Buy milk v3", projectID: projectID),
        )

        #expect(updated.title == "Buy milk v3")
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .update)
    }

    @Test
    func `deleting a task that never synced removes it and its pending create`() async throws {
        let fixture = try await makeRepository(online: false)
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        try await fixture.repository.delete(id: created.id)

        #expect(try await fixture.repository.fetchTasks(projectID: 1).isEmpty)
        let rows = try await fixture.store.read { db in try TaskRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `deleting a synced task while offline hides it immediately but keeps it queued`() async throws {
        let accountID = UUID()
        let network = FakeTaskRepository()
        let store = try LocalStore(directory: temporaryDirectory())
        let project = try await seedProject(in: store, accountID: accountID)
        let projectID: EntityID = project.remoteID.map(EntityID.remote) ?? .local(project.localID)
        let onlineRepository = OfflineTaskRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: network, accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: true),
        )
        let created = try await onlineRepository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: projectID),
        )

        let offlineRepository = OfflineTaskRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: network, accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        try await offlineRepository.delete(id: created.id)

        #expect(try await offlineRepository.fetchTasks(projectID: 1).isEmpty)
        let rows = try await store.read { db in try TaskRecord.fetchAll(db) }
        #expect(rows.count == 1) // still present until the drain actually confirms the delete
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .delete)
    }

    @Test
    func `deleting a synced task while online drains and truly removes the row`() async throws {
        let fixture = try await makeRepository(online: true)
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )

        try await fixture.repository.delete(id: created.id)

        let rows = try await fixture.store.read { db in try TaskRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `searchTasks matches by title across every project`() async throws {
        let fixture = try await makeRepository(online: false)
        _ = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )
        _ = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Write report", projectID: fixture.project),
        )

        let results = try await fixture.repository.searchTasks(query: "milk")

        #expect(results.map(\.title) == ["Buy milk"])
    }

    @Test
    func `fetchTasks never returns another accounts rows`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountA = UUID()
        let accountB = UUID()
        let projectA = try await seedProject(in: store, accountID: accountA)
        let projectB = try await seedProject(in: store, accountID: accountB)
        let networkA = FakeTaskRepository()
        let networkB = FakeTaskRepository()
        let repositoryA = OfflineTaskRepository(
            localStore: store, accountID: accountA,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: networkA, accountID: accountA,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        let repositoryB = OfflineTaskRepository(
            localStore: store, accountID: accountB,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: networkB, accountID: accountB,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        _ = try await repositoryA.create(
            VikunjaTask(id: .local(UUID()), title: "Account A's task", projectID: .local(projectA.localID)),
        )
        _ = try await repositoryB.create(
            VikunjaTask(id: .local(UUID()), title: "Account B's task", projectID: .local(projectB.localID)),
        )

        let tasksA = try await repositoryA.fetchTasks(projectID: 1)
        let tasksB = try await repositoryB.fetchTasks(projectID: 1)

        #expect(tasksA.map(\.title) == ["Account A's task"])
        #expect(tasksB.map(\.title) == ["Account B's task"])
    }

    @Test
    func `fetchTasks resolves a tasks cached label ids against the local label table`() async throws {
        // Regression test: `TaskRecord` has no storage for a task's own
        // fields' worth of label details, only the ids `pullTasks` cached
        // (`TaskRecord.labelRemoteIDs`) - resolving them back to real
        // `Label` values (title, color) by joining against the local
        // `label` table (already synced by `OfflineLabelRepository`) is
        // what makes a synced task's labels show up at all.
        let fixture = try await makeRepository(online: false)
        let labelRow = LabelRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: 5, title: "Urgent", hexColor: "ff0000",
        )
        try await fixture.store.write { db in try labelRow.insert(db) }
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )
        guard case let .local(localID) = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        // Simulates what `pullTasks` would have cached after a real pull -
        // this repository's own `create`/`update` never touch
        // `labelRemoteIDs` themselves (label-on-task association stays
        // online-only, Slice 4).
        try await fixture.store.write { db in
            guard var row = try TaskRecord.fetchOne(db, key: localID) else { return }
            row.labelRemoteIDs = "5"
            try row.save(db)
        }

        let tasks = try await fixture.repository.fetchTasks(projectID: 1)

        #expect(tasks.first?.labels == [Label(id: .remote(5), title: "Urgent", hexColor: "ff0000")])
    }
}
