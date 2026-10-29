import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private struct IgnoringSyncRequests: SyncRequesting {
    func requestSync() async {}
}

struct SyncMutationRaceTests {
    private struct Fixture {
        let repository: OfflineProjectRepository
        let engine: SyncEngine
        let remote: FakeProjectRepository
        let store: LocalStore
    }

    private func fixture() throws -> Fixture {
        let accountID = UUID()
        let store = try LocalStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        let remote = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: remote, labelRepository: FakeLabelRepository(),
            taskRepository: FakeTaskRepository(), relationRepository: FakeTaskRelationRepository(),
            accountID: accountID,
        )
        let repository = OfflineProjectRepository(
            localStore: store,
            accountID: accountID,
            syncRequester: IgnoringSyncRequests(),
        )
        return Fixture(repository: repository, engine: engine, remote: remote, store: store)
    }

    @Test
    func `an edit during create becomes an update without creating a second remote project`() async throws {
        let fixture = try fixture()
        let repository = fixture.repository
        let engine = fixture.engine
        let remote = fixture.remote
        let store = fixture.store
        let original = try await repository.create(Project(id: .local(UUID()), title: "Original"))
        remote.beforeCreateResponse = {
            var edited = original
            edited.title = "Edited during upload"
            _ = try await repository.update(edited)
        }
        try await engine.drainProjectMutations()
        let queue = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.map(\.operation) == [.update])
        try await engine.drainProjectMutations()
        #expect(remote.createdProjects.count == 1)
        #expect(remote.updatedProjects.map(\.title) == ["Edited during upload"])
        #expect(try await repository.fetchProject(id: original.id).title == "Edited during upload")
        #expect(try await store.read { db in try MutationQueueRecord.fetchAll(db).isEmpty })
    }

    @Test
    func `deleting during a create response leaves a durable remote delete`() async throws {
        let fixture = try fixture()
        let repository = fixture.repository
        let engine = fixture.engine
        let remote = fixture.remote
        let store = fixture.store
        let original = try await repository.create(Project(id: .local(UUID()), title: "Remove me"))
        remote.beforeCreateResponse = { try await repository.delete(id: original.id) }
        try await engine.drainProjectMutations()
        #expect(try await repository.fetchProjects().isEmpty)
        #expect(try await store.read { db in try MutationQueueRecord.fetchAll(db).map(\.operation) } == [.delete])
        try await engine.pullProjects()
        #expect(try await repository.fetchProjects().isEmpty)
        try await engine.drainProjectMutations()
        #expect(remote.projects.isEmpty)
        #expect(remote.deletedIDs.count == 1)
        #expect(try await repository.fetchProjects().isEmpty)
    }

    @Test
    func `a failed old upload cannot overwrite a newer queued edit`() async throws {
        let fixture = try fixture()
        let repository = fixture.repository
        let engine = fixture.engine
        let remote = fixture.remote
        let store = fixture.store
        let original = try await repository.create(Project(id: .local(UUID()), title: "Original"))
        try await engine.drainProjectMutations()
        var firstEdit = try await repository.fetchProject(id: original.id)
        firstEdit.title = "First edit"
        let saved = try await repository.update(firstEdit)
        remote.beforeUpdateResponse = {
            var latest = saved
            latest.title = "Newer edit"
            _ = try await repository.update(latest)
        }
        remote.updateError = VikunjaError.network("failed")
        try await engine.drainProjectMutations()
        let items = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(items.count == 1)
        #expect(items[0].status == .pending)
        #expect(items[0].payload?.contains("Newer edit") == true)
        remote.beforeUpdateResponse = nil
        remote.updateError = nil
        try await engine.drainProjectMutations()
        #expect(remote.updatedProjects.map(\.title) == ["Newer edit"])
    }
}
