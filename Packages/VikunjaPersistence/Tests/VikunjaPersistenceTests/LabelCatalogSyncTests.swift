import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct LabelCatalogSyncTests {
    @Test(arguments: [false, true])
    func `failed catalog download preserves offline data and recovers on reconnect`(cancelled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(directory: directory)
        let accountID = UUID()
        let network = FakeLabelRepository()
        network.labels = (1 ... 60).map { Label(id: .remote($0), title: "Label \($0)", hexColor: "") }
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: network,
            taskRepository: FakeTaskRepository(), relationRepository: FakeTaskRelationRepository(),
            accountID: accountID,
        )
        try await engine.pullLabels()
        let repository = OfflineLabelRepository(
            localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        #expect(try await repository.fetchLabels().count == 60)
        let created = try await repository.create(Label(id: 0, title: "Created offline", hexColor: ""))
        _ = try await repository.update(Label(id: .remote(60), title: "Edited offline", hexColor: ""))
        let before = try await snapshot(store)

        // The networking adapter must throw if any page fails, never return the first page as a catalog.
        network.fetchError = cancelled ? CancellationError() : VikunjaError.offline
        await #expect(throws: (any Error).self) { try await engine.pullLabels() }
        #expect(try await snapshot(store) == before)
        #expect(try await repository.fetchLabels().count == 61)

        network.fetchError = nil
        network.labels.append(Label(id: .remote(61), title: "Added on server", hexColor: ""))
        try await engine.pullLabels()
        let recovered = try await repository.fetchLabels()
        #expect(recovered.count == 62)
        #expect(recovered.contains { $0.id == .remote(61) && $0.title == "Added on server" })
        #expect(recovered.contains { $0.id == .remote(60) && $0.title == "Edited offline" })
        #expect(recovered.contains { $0.id == created.id && $0.title == "Created offline" })
        #expect(try await store.read { db in try MutationQueueRecord.fetchAll(db) } == before.mutations)
    }

    private struct Snapshot: Equatable, Sendable {
        let labels: [LabelRecord]
        let mutations: [MutationQueueRecord]
        let syncState: [SyncStateRecord]
    }

    private func snapshot(_ store: LocalStore) async throws -> Snapshot {
        try await store.read { db in
            try Snapshot(
                labels: LabelRecord.fetchAll(db), mutations: MutationQueueRecord.fetchAll(db),
                syncState: SyncStateRecord.fetchAll(db),
            )
        }
    }
}
