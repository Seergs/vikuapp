import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct ProjectSubtreeDeletionTests {
    private struct Fixture {
        let accountID = UUID()
        let store: LocalStore
        let network = FakeProjectRepository()
        let engine: SyncEngine
        let repository: OfflineProjectRepository

        init() throws {
            self.store = try LocalStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))
            self.engine = SyncEngine(
                localStore: store, projectRepository: network,
                labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
            )
            self.repository = OfflineProjectRepository(
                localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
            )
        }

        func seedTree() async throws {
            network.projects = [
                Project(id: 1, title: "Parent"),
                Project(id: 2, title: "Child", parentProjectID: 1),
                Project(id: 3, title: "Grandchild", parentProjectID: 2),
                Project(id: 4, title: "Unrelated"),
            ]
            try await engine.pullProjects()
        }
    }

    @Test
    func `pending parent deletion hides every descendant including direct lookups`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()

        try await fixture.repository.delete(id: 1)

        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])
        for id in 1 ... 3 {
            await #expect(throws: VikunjaError.notFound) {
                try await fixture.repository.fetchProject(id: .remote(id))
            }
        }
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.count == 1)
        #expect(queue.first?.operation == .delete)
    }

    @Test
    func `pull before delete confirmation preserves the hidden subtree and its parent links`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        try await fixture.repository.delete(id: 1)

        // The server still lists the subtree while its delete is pending.
        try await fixture.engine.pullProjects()
        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])

        // The server can also have completed the delete before its response
        // reaches us. Reconciliation must retain the hidden local hierarchy.
        fixture.network.projects.removeAll { $0.id != .remote(4) }
        try await fixture.engine.pullProjects()
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.count == 4)
        #expect(rows.first { $0.remoteID == 2 }?.parentProjectLocalID != nil)
        #expect(rows.first { $0.remoteID == 3 }?.parentProjectLocalID != nil)
        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])
    }

    @Test
    func `confirmed parent deletion removes the entire cached subtree without another pull`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        try await fixture.repository.delete(id: 1)

        try await fixture.engine.drainProjectMutations()

        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [4])
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.isEmpty)
        #expect(fixture.network.deletedIDs == [1])
        try await fixture.engine.pullProjects()
        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])
    }

    @Test
    func `subtree stays hidden while the server delete is in flight`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        let repository = fixture.repository
        let engine = fixture.engine
        fixture.network.beforeDeleteResponse = {
            #expect(try await repository.fetchProjects().map(\.id) == [.remote(4)])
            try await engine.pullProjects()
            #expect(try await repository.fetchProjects().map(\.id) == [.remote(4)])
        }
        try await fixture.repository.delete(id: 1)
        try await fixture.engine.drainProjectMutations()
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [4])
    }

    @Test
    func `deleting a child preserves its parent siblings and another account`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        let otherAccount = UUID()
        let otherEngine = SyncEngine(
            localStore: fixture.store, projectRepository: fixture.network,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(), accountID: otherAccount,
        )
        try await otherEngine.pullProjects()
        let otherRepository = OfflineProjectRepository(
            localStore: fixture.store, accountID: otherAccount, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await otherRepository.update(Project(id: 2, title: "Other account edit", parentProjectID: 1))

        try await fixture.repository.delete(id: 2)
        try await fixture.engine.drainProjectMutations()

        #expect(try await Set(fixture.repository.fetchProjects().map(\.id)) == [.remote(1), .remote(4)])
        #expect(try await fixture.repository.fetchProject(id: 1).parentProjectID == nil)
        #expect(try await otherRepository.fetchProjects().count == 4)
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.count == 1)
        #expect(queue.first?.accountID == otherAccount)
    }

    @Test(arguments: [false, true])
    func `failed or cancelled delete keeps descendants hidden until retry succeeds`(cancelled: Bool) async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        fixture.network.deleteError = cancelled ? CancellationError() : VikunjaError.unauthorized
        try await fixture.repository.delete(id: 1)

        try await fixture.engine.drainProjectMutations()
        try await fixture.engine.pullProjects()
        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.count == 1)
        #expect(queue.first?.status == .failed)

        fixture.network.deleteError = nil
        try await fixture.engine.drainProjectMutations()
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [4])
    }

    @Test
    func `already deleted server parent still clears the cached subtree`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        try await fixture.repository.delete(id: 1)
        fixture.network.deleteError = VikunjaError.notFound

        try await fixture.engine.drainProjectMutations()

        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [4])
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.isEmpty)
    }

    @Test
    func `deleting offline-only tree drops descendants and all their queued writes`() async throws {
        let fixture = try Fixture()
        let parent = try await fixture.repository.create(Project(id: .local(UUID()), title: "Parent"))
        let child = try await fixture.repository.create(Project(
            id: .local(UUID()), title: "Child", parentProjectID: parent.id,
        ))
        _ = try await fixture.repository.create(Project(
            id: .local(UUID()), title: "Grandchild", parentProjectID: child.id,
        ))

        try await fixture.repository.delete(id: parent.id)

        #expect(try await fixture.repository.fetchProjects().isEmpty)
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        #expect(queue.isEmpty)
        #expect(fixture.network.deletedIDs.isEmpty)
    }

    @Test
    func `deletion cancels descendant project task and comment writes but preserves unrelated work`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        _ = try await fixture.repository.update(Project(id: 2, title: "Edited child", parentProjectID: 1))
        _ = try await fixture.repository.create(Project(id: .local(UUID()), title: "Offline child", parentProjectID: 2))
        _ = try await fixture.repository.update(Project(id: 4, title: "Edited unrelated"))
        let tasks = OfflineTaskRepository(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        let task = try await tasks.create(VikunjaTask(id: .local(UUID()), title: "Offline task", projectID: 3))
        let comments = OfflineTaskCommentRepository(
            localStore: fixture.store, accountID: fixture.accountID, syncRequester: NoopKanbanSyncRequester(),
        )
        _ = try await comments.addComment("Offline comment", toTask: task.id)

        try await fixture.repository.delete(id: 1)
        let queue = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(queue.count == 2)
        #expect(queue.allSatisfy { $0.entityType == .project })
        try await fixture.engine.drainProjectMutations()

        #expect(fixture.network.createdProjects.isEmpty)
        #expect(fixture.network.updatedProjects.map(\.id) == [.remote(4)])
        let taskRows = try await fixture.store.read { db in try TaskRecord.fetchAll(db) }
        let commentRows = try await fixture.store.read { db in try TaskCommentRecord.fetchAll(db) }
        #expect(taskRows.isEmpty)
        #expect(commentRows.isEmpty)
    }

    @Test
    func `synced child moved under an offline-only parent still gets deleted remotely`() async throws {
        let fixture = try Fixture()
        try await fixture.seedTree()
        let parent = try await fixture.repository.create(Project(id: .local(UUID()), title: "Offline parent"))
        _ = try await fixture.repository.update(Project(id: 1, title: "Moved", parentProjectID: parent.id))

        try await fixture.repository.delete(id: parent.id)
        #expect(try await fixture.repository.fetchProjects().map(\.id) == [.remote(4)])
        try await fixture.engine.drainProjectMutations()

        #expect(fixture.network.createdProjects.isEmpty)
        #expect(fixture.network.deletedIDs == [1])
        let rows = try await fixture.store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [4])
    }
}
