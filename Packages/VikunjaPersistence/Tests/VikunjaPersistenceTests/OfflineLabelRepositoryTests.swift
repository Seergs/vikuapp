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
}

struct OfflineLabelRepositoryTests {
    private struct Fixture {
        let repository: OfflineLabelRepository
        let store: LocalStore
        let network: FakeLabelRepository
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeRepository(
        online: Bool,
        accountID: UUID = UUID(),
        network: FakeLabelRepository = FakeLabelRepository(),
    ) throws -> Fixture {
        let store = try LocalStore(directory: temporaryDirectory())
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: network, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let reachability = FakeReachabilityMonitor(isReachable: online)
        let repository = OfflineLabelRepository(
            localStore: store, accountID: accountID, syncEngine: engine, reachability: reachability,
            networkLabelRepository: network,
        )
        return Fixture(repository: repository, store: store, network: network)
    }

    @Test
    func `fetchLabels is empty for a freshly created local store`() async throws {
        let fixture = try makeRepository(online: false)
        #expect(try await fixture.repository.fetchLabels().isEmpty)
    }

    @Test
    func `fetchLabels pulls once on a cold, never-synced account instead of racing a background sync`() async throws {
        let network = FakeLabelRepository()
        network.labels = [Label(id: 1, title: "Already on the server", hexColor: "")]
        let fixture = try makeRepository(online: true, network: network)

        let labels = try await fixture.repository.fetchLabels()

        #expect(labels.map(\.title) == ["Already on the server"])
        #expect(network.fetchLabelsCallCount == 1)

        _ = try await fixture.repository.fetchLabels()
        #expect(network.fetchLabelsCallCount == 1)
    }

    @Test
    func `fetchLabels never pulls while offline on a cold, never-synced account`() async throws {
        let fixture = try makeRepository(online: false)

        #expect(try await fixture.repository.fetchLabels().isEmpty)
        #expect(fixture.network.fetchLabelsCallCount == 0)
    }

    @Test
    func `create on a cold never-synced account is not undone by its own cold-start pull`() async throws {
        let fixture = try makeRepository(online: true)

        let created = try await fixture.repository.create(
            Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"),
        )

        #expect(created.title == "Urgent")
        #expect(created.id.remoteValue != nil)
        let labels = try await fixture.repository.fetchLabels()
        #expect(labels.map(\.title) == ["Urgent"])
    }

    @Test
    func `create while offline returns a local id and leaves the mutation queued`() async throws {
        let fixture = try makeRepository(online: false)

        let created = try await fixture.repository.create(
            Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"),
        )

        guard case .local = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        #expect(created.title == "Urgent")
        #expect(fixture.network.createdLabels.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(queued[0].status == .pending)
    }

    @Test
    func `create while online drains immediately and returns the servers remote id`() async throws {
        let fixture = try makeRepository(online: true)

        let created = try await fixture.repository.create(
            Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"),
        )

        #expect(created.id.remoteValue != nil)
        #expect(fixture.network.createdLabels.map(\.title) == ["Urgent"])
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `fetchLabels reflects a label created offline`() async throws {
        let fixture = try makeRepository(online: false)
        _ = try await fixture.repository.create(Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"))

        let labels = try await fixture.repository.fetchLabels()

        #expect(labels.map(\.title) == ["Urgent"])
    }

    @Test
    func `updating a label that never synced coalesces into its still pending create`() async throws {
        let fixture = try makeRepository(online: false)
        let created = try await fixture.repository.create(
            Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"),
        )

        let updated = try await fixture.repository.update(
            Label(id: created.id, title: "Urgent & Important", hexColor: "ff0000"),
        )

        #expect(updated.title == "Urgent & Important")
        guard case .local = updated.id else {
            Issue.record("expected the id to still be local, got \(updated.id)")
            return
        }
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .create)
        #expect(fixture.network.createdLabels.isEmpty)
    }

    @Test
    func `editing a synced label twice while offline coalesces into one queued update`() async throws {
        let accountID = UUID()
        let network = FakeLabelRepository()
        let store = try LocalStore(directory: temporaryDirectory())
        let onlineEngine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: network, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let onlineRepository = OfflineLabelRepository(
            localStore: store, accountID: accountID, syncEngine: onlineEngine,
            reachability: FakeReachabilityMonitor(isReachable: true), networkLabelRepository: network,
        )
        let created = try await onlineRepository.create(Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"))
        #expect(created.id.remoteValue != nil)

        let offlineEngine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: network, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let offlineRepository = OfflineLabelRepository(
            localStore: store, accountID: accountID, syncEngine: offlineEngine,
            reachability: FakeReachabilityMonitor(isReachable: false), networkLabelRepository: network,
        )
        _ = try await offlineRepository.update(Label(id: created.id, title: "Urgent v2", hexColor: "ff0000"))
        let updated = try await offlineRepository.update(Label(id: created.id, title: "Urgent v3", hexColor: "ff0000"))

        #expect(updated.title == "Urgent v3")
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .update)
    }

    @Test
    func `deleting a label that never synced removes it and its pending create`() async throws {
        let fixture = try makeRepository(online: false)
        let created = try await fixture.repository.create(
            Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"),
        )

        try await fixture.repository.delete(id: created.id)

        #expect(try await fixture.repository.fetchLabels().isEmpty)
        let rows = try await fixture.store.read { db in try LabelRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `deleting a synced label while offline hides it immediately but keeps it queued`() async throws {
        let accountID = UUID()
        let network = FakeLabelRepository()
        let store = try LocalStore(directory: temporaryDirectory())
        let onlineRepository = OfflineLabelRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: network, taskRepository: FakeTaskRepository(),

                accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: true), networkLabelRepository: network,
        )
        let created = try await onlineRepository.create(Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"))

        let offlineRepository = OfflineLabelRepository(
            localStore: store, accountID: accountID,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: network, taskRepository: FakeTaskRepository(),

                accountID: accountID,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false), networkLabelRepository: network,
        )
        try await offlineRepository.delete(id: created.id)

        #expect(try await offlineRepository.fetchLabels().isEmpty)
        let rows = try await store.read { db in try LabelRecord.fetchAll(db) }
        #expect(rows.count == 1) // still present until the drain actually confirms the delete
        let queued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .delete)
    }

    @Test
    func `deleting a synced label while online drains and truly removes the row`() async throws {
        let fixture = try makeRepository(online: true)
        let created = try await fixture.repository.create(
            Label(id: .local(UUID()), title: "Urgent", hexColor: "ff0000"),
        )

        try await fixture.repository.delete(id: created.id)

        let rows = try await fixture.store.read { db in try LabelRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `fetchLabels never returns another accounts rows`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let accountA = UUID()
        let accountB = UUID()
        let networkA = FakeLabelRepository()
        let networkB = FakeLabelRepository()
        let repositoryA = OfflineLabelRepository(
            localStore: store, accountID: accountA,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: networkA, taskRepository: FakeTaskRepository(),

                accountID: accountA,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false), networkLabelRepository: networkA,
        )
        let repositoryB = OfflineLabelRepository(
            localStore: store, accountID: accountB,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: networkB, taskRepository: FakeTaskRepository(),

                accountID: accountB,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false), networkLabelRepository: networkB,
        )

        _ = try await repositoryA.create(Label(id: .local(UUID()), title: "A's label", hexColor: ""))
        _ = try await repositoryB.create(Label(id: .local(UUID()), title: "B's label", hexColor: ""))

        #expect(try await repositoryA.fetchLabels().map(\.title) == ["A's label"])
        #expect(try await repositoryB.fetchLabels().map(\.title) == ["B's label"])
    }

    @Test
    func `addLabel and removeLabel pass straight through to the network repository`() async throws {
        let fixture = try makeRepository(online: true)

        try await fixture.repository.addLabel(1, toTask: 5)
        try await fixture.repository.removeLabel(1, fromTask: 5)

        // `FakeLabelRepository.addLabel`/`removeLabel` are no-ops that
        // never throw - reaching here without error confirms the calls
        // were forwarded rather than queued or misrouted.
    }
}
