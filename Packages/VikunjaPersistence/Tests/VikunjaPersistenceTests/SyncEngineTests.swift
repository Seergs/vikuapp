import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct SyncEngineTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test
    func `pullProjects inserts a project not yet seen locally`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Groceries", hexColor: "ff0000")]
        let engine = SyncEngine(localStore: store, projectRepository: repository)

        try await engine.pullProjects()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.count == 1)
        #expect(rows[0].remoteID == 1)
        #expect(rows[0].title == "Groceries")
        #expect(rows[0].hexColor == "ff0000")
    }

    @Test
    func `pullProjects updates an existing row in place rather than duplicating it`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Groceries")]
        let engine = SyncEngine(localStore: store, projectRepository: repository)
        try await engine.pullProjects()
        let localID = try await store.read { db in
            try #require(ProjectRecord.fetchAll(db).first { $0.remoteID == 1 }).localID
        }

        repository.projects = [Project(id: 1, title: "Groceries (renamed)")]
        try await engine.pullProjects()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.count == 1)
        #expect(rows[0].localID == localID)
        #expect(rows[0].title == "Groceries (renamed)")
    }

    @Test
    func `pullProjects resolves a childs parent link regardless of array order`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        // The child appears before its parent in the server's response.
        repository.projects = [
            Project(id: 2, title: "Subproject", parentProjectID: 1),
            Project(id: 1, title: "Parent"),
        ]
        let engine = SyncEngine(localStore: store, projectRepository: repository)

        try await engine.pullProjects()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        let parent = try #require(rows.first { $0.remoteID == 1 })
        let child = try #require(rows.first { $0.remoteID == 2 })
        #expect(child.parentProjectLocalID == parent.localID)
    }

    @Test
    func `pullProjects deletes a local row whose remote id is gone from the server`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Groceries"), Project(id: 2, title: "Work")]
        let engine = SyncEngine(localStore: store, projectRepository: repository)
        try await engine.pullProjects()

        repository.projects = [Project(id: 1, title: "Groceries")]
        try await engine.pullProjects()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.map(\.remoteID) == [1])
    }

    @Test
    func `pullProjects keeps a local row with a pending mutation even once the server stops returning it`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Groceries")]
        let engine = SyncEngine(localStore: store, projectRepository: repository)
        try await engine.pullProjects()
        let localID = try await store.read { db in
            try #require(ProjectRecord.fetchAll(db).first { $0.remoteID == 1 }).localID
        }
        try await store.write { db in
            var mutation = MutationQueueRecord(
                id: nil, entityType: .project, operation: .update, targetLocalID: localID,
                payload: nil, createdAt: Date(), retryCount: 0, lastError: nil, status: .pending,
            )
            try mutation.insert(db)
        }

        repository.projects = []
        try await engine.pullProjects()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.count == 1)
        #expect(rows[0].localID == localID)
    }

    @Test
    func `pullProjects deletes a local row once its queued mutation is no longer pending or inFlight`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Groceries")]
        let engine = SyncEngine(localStore: store, projectRepository: repository)
        try await engine.pullProjects()
        let localID = try await store.read { db in
            try #require(ProjectRecord.fetchAll(db).first { $0.remoteID == 1 }).localID
        }
        try await store.write { db in
            var mutation = MutationQueueRecord(
                id: nil, entityType: .project, operation: .update, targetLocalID: localID,
                payload: nil, createdAt: Date(), retryCount: 3, lastError: "boom", status: .failed,
            )
            try mutation.insert(db)
        }

        repository.projects = []
        try await engine.pullProjects()

        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.isEmpty)
    }

    @Test
    func `pullProjects records the pull time in syncState`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(localStore: store, projectRepository: repository)
        let before = Date()

        try await engine.pullProjects()

        let state = try await store.read { db in try SyncStateRecord.fetchAll(db) }
        #expect(state.count == 1)
        #expect(state[0].entityType == .project)
        // GRDB's `.datetime` column storage truncates sub-second precision,
        // so the round-tripped value can read slightly earlier than the
        // in-memory `before` it was captured just ahead of.
        #expect(state[0].lastPulledAt >= before.addingTimeInterval(-1))
    }
}
