import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

private actor FilterReachability: ReachabilityMonitoring {
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

struct OfflineFilterRepositoryTests {
    private struct Fixture {
        let repository: OfflineFilterRepository
        let projectRepository: OfflineProjectRepository
        let localStore: LocalStore
        let engine: SyncEngine
        let networkProjects: FakeProjectRepository
        let networkFilters: FakeFilterRepository
        let reachability: FilterReachability
        let accountID: UUID
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeFixture(online: Bool) async throws -> Fixture {
        let accountID = UUID()
        let localStore = try LocalStore(directory: temporaryDirectory())
        let networkProjects = FakeProjectRepository()
        networkProjects.projects = [Project(id: -8, title: "Original filter")]
        let networkFilters = FakeFilterRepository()
        networkFilters.filters[7] = SavedFilterDetail(
            id: 7, title: "Original filter", description: "", isFavorite: false, query: "priority >= 3",
        )
        let reachability = FilterReachability(isReachable: online)
        let engine = SyncEngine(
            localStore: localStore,
            projectRepository: networkProjects,
            labelRepository: FakeLabelRepository(),
            taskRepository: FakeTaskRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: networkFilters,
            accountID: accountID,
        )
        try await engine.pullProjects()
        let repository = OfflineFilterRepository(
            localStore: localStore,
            accountID: accountID,
            networkRepository: networkFilters,
            syncEngine: engine,
            reachability: reachability,
        )
        let projectRepository = OfflineProjectRepository(
            localStore: localStore,
            accountID: accountID,
            syncEngine: engine,
            reachability: reachability,
        )
        return Fixture(
            repository: repository,
            projectRepository: projectRepository,
            localStore: localStore,
            engine: engine,
            networkProjects: networkProjects,
            networkFilters: networkFilters,
            reachability: reachability,
            accountID: accountID,
        )
    }

    @Test
    func `fetchFilter stores query and can serve it offline`() async throws {
        let fixture = try await makeFixture(online: true)

        let first = try await fixture.repository.fetchFilter(id: 7)
        #expect(first.query == "priority >= 3")
        #expect(fixture.networkFilters.fetchedIDs == [7])

        await fixture.reachability.setReachable(false)
        fixture.networkFilters.fetchError = VikunjaError.network("offline")
        #expect(try await fixture.repository.fetchFilter(id: 7).query == first.query)
        #expect(fixture.networkFilters.fetchedIDs == [7])
    }

    @Test
    func `fetchFilter returns cache immediately and refreshes it in background`() async throws {
        let fixture = try await makeFixture(online: true)
        _ = try await fixture.repository.fetchFilter(id: 7)
        fixture.networkFilters.filters[7] = SavedFilterDetail(
            id: 7, title: "Original filter", description: "", isFavorite: false, query: "done = false",
        )

        let cached = try await fixture.repository.fetchFilter(id: 7)
        #expect(cached.query == "priority >= 3")

        for _ in 0 ..< 100 {
            let storedQuery = try await fixture.localStore.read { db in
                try SavedFilterRecord.fetchAll(db).first?.query
            }
            if storedQuery == "done = false" {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let refreshedQuery = try await fixture.localStore.read { db in
            try SavedFilterRecord.fetchAll(db).first?.query
        }
        #expect(refreshedQuery == "done = false")
    }

    @Test
    func `offline rename updates project title and coalesces queued edits`() async throws {
        let fixture = try await makeFixture(online: false)

        _ = try await fixture.repository.renameFilter(id: 7, title: "First title")
        _ = try await fixture.repository.renameFilter(id: 7, title: "Final title")
        let projects = try await fixture.projectRepository.fetchProjects()
        let updated = try #require(projects.first { $0.savedFilterID == 7 })
        let mutations = try await fixture.localStore.read { db in
            try MutationQueueRecord.fetchAll(db).filter { $0.entityType == .filter }
        }

        #expect(updated.title == "Final title")
        #expect(mutations.count == 1)
        #expect(mutations[0].operation == .update)
        #expect(fixture.networkFilters.renamed.isEmpty)
        let statuses = try await fixture.localStore.pendingSyncStatuses(accountID: fixture.accountID)
        #expect(statuses[SyncItemKey(kind: .project, id: .remote(-8))] == .pending)
    }

    @Test
    func `project pull does not overwrite a queued filter rename`() async throws {
        let fixture = try await makeFixture(online: false)
        _ = try await fixture.repository.renameFilter(id: 7, title: "Local title")

        try await fixture.engine.pullProjects()

        let projects = try await fixture.projectRepository.fetchProjects()
        #expect(projects.first { $0.savedFilterID == 7 }?.title == "Local title")
    }

    @Test
    func `filter delete supersedes queued rename and remains hidden after failed drain`() async throws {
        let fixture = try await makeFixture(online: false)
        fixture.networkFilters.deleteError = VikunjaError.network("offline")
        _ = try await fixture.repository.renameFilter(id: 7, title: "Rename before delete")
        await fixture.reachability.setReachable(true)

        try await fixture.repository.deleteFilter(id: 7)
        try await fixture.engine.pullProjects()

        let visible = try await fixture.projectRepository.fetchProjects()
        let remaining = try await fixture.localStore.read { db in
            try (
                ProjectRecord.fetchAll(db).first { $0.remoteID == -8 },
                SavedFilterRecord.fetchAll(db).first { $0.remoteID == 7 },
                MutationQueueRecord.fetchAll(db).filter { $0.entityType == .filter },
            )
        }
        #expect(!visible.contains { $0.savedFilterID == 7 })
        #expect(remaining.0 != nil)
        #expect(remaining.1 != nil)
        #expect(remaining.2.count == 1)
        #expect(remaining.2[0].operation == .delete)
        #expect(remaining.2[0].status == .failed)
        let operations = try await fixture.localStore.pendingSyncOperations(accountID: fixture.accountID)
        #expect(operations.first?.entity == .filter)
        #expect(operations.first?.action == .delete)
        #expect(operations.first?.targetTitle == "Rename before delete")
    }

    @Test
    func `successful filter delete removes project query and queue row`() async throws {
        let fixture = try await makeFixture(online: false)
        try await fixture.repository.deleteFilter(id: 7)

        fixture.networkFilters.deleteError = nil
        try await fixture.engine.drainFilterMutations()

        let remaining = try await fixture.localStore.read { db in
            try (
                ProjectRecord.fetchAll(db).filter { $0.remoteID == -8 },
                SavedFilterRecord.fetchAll(db).filter { $0.remoteID == 7 },
                MutationQueueRecord.fetchAll(db).filter { $0.entityType == .filter },
            )
        }
        #expect(remaining.0.isEmpty)
        #expect(remaining.1.isEmpty)
        #expect(remaining.2.isEmpty)
        #expect(fixture.networkFilters.deletedIDs == [7])
    }
}
