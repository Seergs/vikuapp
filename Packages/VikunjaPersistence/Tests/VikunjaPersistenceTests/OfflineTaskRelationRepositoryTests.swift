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

struct OfflineTaskRelationRepositoryTests {
    private struct Fixture {
        let repository: OfflineTaskRelationRepository
        let store: LocalStore
        let network: FakeTaskRelationRepository
        let projectLocalID: UUID
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeRepository(
        online: Bool,
        accountID: UUID,
        network: FakeTaskRelationRepository = FakeTaskRelationRepository(),
    ) async throws -> Fixture {
        let store = try LocalStore(directory: temporaryDirectory())
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: FakeTaskRepository(), relationRepository: network, accountID: accountID,
        )
        let reachability = FakeReachabilityMonitor(isReachable: online)
        let repository = OfflineTaskRelationRepository(
            localStore: store, accountID: accountID,
            syncRequester: TestSyncRequester(engine: engine, reachability: reachability),
        )
        let projectRow = ProjectRecord(
            localID: UUID(), accountID: accountID, remoteID: 1, title: "Groceries", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        try await store.write { db in try projectRow.insert(db) }
        return Fixture(repository: repository, store: store, network: network, projectLocalID: projectRow.localID)
    }

    @discardableResult
    private func seedTask(
        in fixture: Fixture, accountID: UUID, remoteID: Int?, title: String = "Buy milk",
    ) async throws -> TaskRecord {
        let taskRow = TaskRecord(
            localID: UUID(), accountID: accountID, remoteID: remoteID, title: title, description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: fixture.projectLocalID, serverUpdatedAt: nil,
        )
        try await fixture.store.write { db in try taskRow.insert(db) }
        return taskRow
    }

    @Test
    func `addRelation while online drains immediately, attaches via the network, and patches the cache on both sides`(
    ) async throws {
        let accountID = UUID()
        let fixture = try await makeRepository(online: true, accountID: accountID)
        try await seedTask(in: fixture, accountID: accountID, remoteID: 5, title: "Write report")
        try await seedTask(in: fixture, accountID: accountID, remoteID: 6, title: "Outline")

        try await fixture.repository.addRelation(kind: .subtask, otherTaskID: .remote(6), toTask: .remote(5))

        #expect(fixture.network.addedRelations.map(\.kind) == [.subtask])
        #expect(fixture.network.addedRelations.map(\.taskID) == [.remote(5)])
        #expect(fixture.network.addedRelations.map(\.otherTaskID) == [.remote(6)])
        let relations = try await fixture.store.read { db in try TaskRelationRecord.fetchAll(db) }
        let forward = try #require(relations.first { $0.otherTaskRemoteID == 6 })
        #expect(forward.kind == .subtask)
        #expect(forward.title == "Outline")
        // The other side gets the inverse kind cached too, so its own
        // relation list shows this without waiting for its own next pull.
        let mirror = try #require(relations.first { $0.otherTaskRemoteID == 5 })
        #expect(mirror.kind == .parenttask)
        #expect(mirror.title == "Write report")
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.isEmpty)
    }

    @Test
    func `removeRelation while online drains immediately and clears the cache on both sides`() async throws {
        let accountID = UUID()
        let fixture = try await makeRepository(online: true, accountID: accountID)
        try await seedTask(in: fixture, accountID: accountID, remoteID: 5, title: "Write report")
        try await seedTask(in: fixture, accountID: accountID, remoteID: 6, title: "Outline")
        try await fixture.repository.addRelation(kind: .subtask, otherTaskID: .remote(6), toTask: .remote(5))

        try await fixture.repository.removeRelation(kind: .subtask, otherTaskID: .remote(6), fromTask: .remote(5))

        #expect(fixture.network.removedRelations.map(\.kind) == [.subtask])
        let relations = try await fixture.store.read { db in try TaskRelationRecord.fetchAll(db) }
        #expect(relations.isEmpty)
    }

    @Test
    func `addRelation while offline queues without reaching the network`() async throws {
        let accountID = UUID()
        let fixture = try await makeRepository(online: false, accountID: accountID)
        try await seedTask(in: fixture, accountID: accountID, remoteID: 5)
        try await seedTask(in: fixture, accountID: accountID, remoteID: 6)

        try await fixture.repository.addRelation(kind: .subtask, otherTaskID: .remote(6), toTask: .remote(5))

        #expect(fixture.network.addedRelations.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .addRelation)
        #expect(queued[0].status == .pending)
    }

    @Test
    func `addRelation queued against a task that has not synced yet defers until it resolves`() async throws {
        let accountID = UUID()
        let fixture = try await makeRepository(online: true, accountID: accountID)
        let taskRow = try await seedTask(in: fixture, accountID: accountID, remoteID: nil)
        try await seedTask(in: fixture, accountID: accountID, remoteID: 6)

        try await fixture.repository.addRelation(
            kind: .subtask, otherTaskID: .remote(6), toTask: .local(taskRow.localID),
        )

        #expect(fixture.network.addedRelations.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .addRelation)
        #expect(queued[0].status == .pending)
    }

    @Test
    func `addRelation queued against the other task that has not synced yet defers until it resolves`() async throws {
        let accountID = UUID()
        let fixture = try await makeRepository(online: true, accountID: accountID)
        try await seedTask(in: fixture, accountID: accountID, remoteID: 5)
        let otherTaskRow = try await seedTask(in: fixture, accountID: accountID, remoteID: nil)

        try await fixture.repository.addRelation(
            kind: .subtask, otherTaskID: .local(otherTaskRow.localID), toTask: .remote(5),
        )

        #expect(fixture.network.addedRelations.isEmpty)
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queued.count == 1)
        #expect(queued[0].operation == .addRelation)
        #expect(queued[0].status == .pending)
    }
}
