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
            labelRepository: FakeLabelRepository(), taskRepository: network,
            relationRepository: FakeTaskRelationRepository(), accountID: accountID,
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
    func `fetchTasks reads virtual membership while keeping the real project on the task`() async throws {
        let fixture = try await makeRepository(online: false)
        let favorites = ProjectRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: -1, title: "Favorites", description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: nil, position: 0, hexColor: "",
            serverUpdatedAt: nil,
        )
        // Resolve the real project's local id rather than ever assigning the
        // Favorites id to TaskRecord.projectLocalID.
        let realProject = try await fixture.store.read { db in
            try #require(ProjectRecord.fetchAll(db).first { $0.remoteID == 1 })
        }
        let realTask = TaskRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: 10, title: "Buy milk", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: realProject.localID, serverUpdatedAt: nil,
        )
        try await fixture.store.write { db in
            try favorites.insert(db)
            try realTask.insert(db)
            try VirtualProjectTaskRecord(
                accountID: fixture.accountID,
                projectLocalID: favorites.localID,
                taskLocalID: realTask.localID,
                position: 0,
            ).insert(db)
        }

        let fetched = try await fixture.repository.fetchTasks(projectID: -1)

        #expect(fetched.map(\.title) == ["Buy milk"])
        #expect(fetched.first?.projectID == 1)

        _ = try await fixture.store.write { db in try realTask.delete(db) }
        let afterTaskDeletion = try await fixture.store.read { db in
            try VirtualProjectTaskRecord.fetchAll(db)
        }
        #expect(afterTaskDeletion.isEmpty)

        try await fixture.store.write { db in
            try realTask.insert(db)
            try VirtualProjectTaskRecord(
                accountID: fixture.accountID,
                projectLocalID: favorites.localID,
                taskLocalID: realTask.localID,
                position: 0,
            ).insert(db)
            try favorites.delete(db)
        }
        let afterProjectDeletion = try await fixture.store.read { db in
            try VirtualProjectTaskRecord.fetchAll(db)
        }
        #expect(afterProjectDeletion.isEmpty)
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
    func `create persists reminders locally`() async throws {
        let fixture = try await makeRepository(online: false)
        let reminder = TaskReminder(reminder: Date(timeIntervalSince1970: 2_000_000_000))

        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project, reminders: [reminder]),
        )

        #expect(created.reminders == [reminder])
        let fetched = try await fixture.repository.fetchTask(id: created.id)
        #expect(fetched.reminders == [reminder])
    }

    @Test
    func `update replaces a tasks reminders`() async throws {
        let fixture = try await makeRepository(online: false)
        let first = TaskReminder(reminder: Date(timeIntervalSince1970: 2_000_000_000))
        let second = TaskReminder(
            reminder: Date(timeIntervalSince1970: 2_000_100_000), relativePeriod: -3600, relativeTo: .dueDate,
        )
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project, reminders: [first]),
        )

        let updated = try await fixture.repository.update(
            VikunjaTask(
                id: created.id, title: "Buy milk", projectID: fixture.project, reminders: [second],
            ),
        )

        #expect(updated.reminders == [second])
        let fetched = try await fixture.repository.fetchTask(id: created.id)
        #expect(fetched.reminders == [second])
    }

    @Test
    func `update clears a tasks reminders when the new state has none`() async throws {
        let fixture = try await makeRepository(online: false)
        let reminder = TaskReminder(reminder: Date(timeIntervalSince1970: 2_000_000_000))
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project, reminders: [reminder]),
        )

        let updated = try await fixture.repository.update(
            VikunjaTask(id: created.id, title: "Buy milk", projectID: fixture.project),
        )

        #expect(updated.reminders.isEmpty)
        let fetched = try await fixture.repository.fetchTask(id: created.id)
        #expect(fetched.reminders.isEmpty)
    }

    @Test
    func `online create pushes reminders to the network and keeps the echoed set`() async throws {
        let fixture = try await makeRepository(online: true)
        let reminder = TaskReminder(reminder: Date(timeIntervalSince1970: 2_000_000_000))

        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project, reminders: [reminder]),
        )

        #expect(fixture.network.createdTasks.first?.reminders == [reminder])
        #expect(created.reminders == [reminder])
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
                labelRepository: FakeLabelRepository(), taskRepository: network,
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
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
                labelRepository: FakeLabelRepository(), taskRepository: network,
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
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
                labelRepository: FakeLabelRepository(), taskRepository: network,
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
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
                labelRepository: FakeLabelRepository(), taskRepository: network,
                relationRepository: FakeTaskRelationRepository(), accountID: accountID,
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
                labelRepository: FakeLabelRepository(), taskRepository: networkA,
                relationRepository: FakeTaskRelationRepository(), accountID: accountA,
            ),
            reachability: FakeReachabilityMonitor(isReachable: false),
        )
        let repositoryB = OfflineTaskRepository(
            localStore: store, accountID: accountB,
            syncEngine: SyncEngine(
                localStore: store, projectRepository: FakeProjectRepository(),
                labelRepository: FakeLabelRepository(), taskRepository: networkB,
                relationRepository: FakeTaskRelationRepository(), accountID: accountB,
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
        // `labelRemoteIDs` themselves; it's `SyncEngine.drainTaskLabelMutation`
        // that patches it, once an `addLabel`/`removeLabel` actually drains.
        try await fixture.store.write { db in
            guard var row = try TaskRecord.fetchOne(db, key: localID) else { return }
            row.labelRemoteIDs = "5"
            try row.save(db)
        }

        let tasks = try await fixture.repository.fetchTasks(projectID: 1)

        #expect(tasks.first?.labels == [Label(id: .remote(5), title: "Urgent", hexColor: "ff0000")])
    }

    private func queueTaskLabelMutation(
        operation: MutationOperation,
        taskLocalID: UUID,
        labelLocalID: UUID,
        accountID: UUID,
        in store: LocalStore,
    ) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try String(
            data: encoder.encode(TaskLabelMutationPayload(labelLocalID: labelLocalID)), encoding: .utf8,
        )
        try await store.write { db in
            var item = MutationQueueRecord(
                id: nil, accountID: accountID, entityType: .task, operation: operation, targetLocalID: taskLocalID,
                payload: payload, createdAt: Date(), retryCount: 0, lastError: nil, status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
    }

    @Test
    func `fetchTasks shows a label still only queued, before the attach has synced`() async throws {
        // Regression test: a label attached to a task that's still entirely
        // local (neither the task nor the label has a remote id yet, or the
        // device is simply offline) used to be invisible everywhere, since
        // `TaskRecord.labelRemoteIDs` only gets patched once
        // `drainTaskLabelMutation` actually succeeds - a queued-but-not-yet-
        // drained `addLabel` must still show up immediately.
        let fixture = try await makeRepository(online: false)
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )
        guard case let .local(taskLocalID) = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        let labelRow = LabelRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: nil, title: "Urgent", hexColor: "ff0000",
        )
        try await fixture.store.write { db in try labelRow.insert(db) }
        try await queueTaskLabelMutation(
            operation: .addLabel, taskLocalID: taskLocalID, labelLocalID: labelRow.localID,
            accountID: fixture.accountID, in: fixture.store,
        )

        let tasks = try await fixture.repository.fetchTasks(projectID: 1)

        #expect(tasks.first?.labels == [Label(id: .local(labelRow.localID), title: "Urgent", hexColor: "ff0000")])
    }

    @Test
    func `fetchTask hides a cached label once its removal is queued, before the drain confirms it`() async throws {
        let fixture = try await makeRepository(online: false)
        let labelRow = LabelRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: 5, title: "Urgent", hexColor: "ff0000",
        )
        try await fixture.store.write { db in try labelRow.insert(db) }
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: fixture.project),
        )
        guard case let .local(taskLocalID) = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        try await fixture.store.write { db in
            guard var row = try TaskRecord.fetchOne(db, key: taskLocalID) else { return }
            row.labelRemoteIDs = "5"
            try row.save(db)
        }
        try await queueTaskLabelMutation(
            operation: .removeLabel, taskLocalID: taskLocalID, labelLocalID: labelRow.localID,
            accountID: fixture.accountID, in: fixture.store,
        )

        let task = try await fixture.repository.fetchTask(id: created.id)

        #expect(task.labels.isEmpty)
    }

    private func queueTaskRelationMutation(
        operation: MutationOperation,
        taskLocalID: UUID,
        kind: RelationKind,
        otherTaskLocalID: UUID,
        in fixture: Fixture,
    ) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try String(
            data: encoder.encode(TaskRelationMutationPayload(kind: kind, otherTaskLocalID: otherTaskLocalID)),
            encoding: .utf8,
        )
        try await fixture.store.write { db in
            var item = MutationQueueRecord(
                id: nil, accountID: fixture.accountID, entityType: .task, operation: operation,
                targetLocalID: taskLocalID, payload: payload, createdAt: Date(), retryCount: 0, lastError: nil,
                status: .pending, needsConflictResolution: false,
            )
            try item.insert(db)
        }
    }

    @Test
    func `fetchTasks shows a relation still only queued, before the attach has synced`() async throws {
        // Regression test: a relation between two tasks that are still
        // entirely local (neither has a remote id yet) used to be invisible
        // everywhere, since the `taskRelation` cache table only gets
        // patched once `drainTaskRelationMutation` actually succeeds - a
        // queued-but-not-yet-drained `addRelation` must still show up
        // immediately.
        let fixture = try await makeRepository(online: false)
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Write report", projectID: fixture.project),
        )
        guard case let .local(taskLocalID) = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        let otherTask = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Outline", projectID: fixture.project),
        )
        guard case let .local(otherTaskLocalID) = otherTask.id else {
            Issue.record("expected a local id while offline, got \(otherTask.id)")
            return
        }
        try await queueTaskRelationMutation(
            operation: .addRelation, taskLocalID: taskLocalID, kind: .subtask, otherTaskLocalID: otherTaskLocalID,
            in: fixture,
        )

        let task = try await fixture.repository.fetchTask(id: created.id)

        #expect(task.subtasks == [TaskRelation(id: otherTask.id, title: "Outline", projectID: fixture.project)])
    }

    @Test
    func `fetchTask shows the inverse side of a relation queued from the other task, before either has synced`() async throws {
        // Regression test: `addRelation` is queued from the owner task's
        // perspective only (`TaskRelationMutationPayload.otherTaskLocalID`
        // identifies the other side), so the other task's own screen used
        // to show nothing until a drain actually ran - even though both
        // sides of the relation are already fully known locally. Opening
        // the *other* task's screen while both are still local-only must
        // show the inverse relation (here, `parenttask`, the mirror of
        // `subtask`) immediately too.
        let fixture = try await makeRepository(online: false)
        let owner = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Write report", projectID: fixture.project),
        )
        guard case let .local(ownerLocalID) = owner.id else {
            Issue.record("expected a local id while offline, got \(owner.id)")
            return
        }
        let otherTask = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Outline", projectID: fixture.project),
        )
        guard case let .local(otherTaskLocalID) = otherTask.id else {
            Issue.record("expected a local id while offline, got \(otherTask.id)")
            return
        }
        try await queueTaskRelationMutation(
            operation: .addRelation, taskLocalID: ownerLocalID, kind: .subtask,
            otherTaskLocalID: otherTaskLocalID, in: fixture,
        )

        let task = try await fixture.repository.fetchTask(id: otherTask.id)

        let expected = TaskRelation(id: owner.id, title: "Write report", projectID: fixture.project)
        #expect(task.otherRelations[.parenttask] == [expected])
    }

    @Test
    func `fetchTask hides a cached relation once its removal is queued, before the drain confirms it`() async throws {
        let fixture = try await makeRepository(online: false)
        let created = try await fixture.repository.create(
            VikunjaTask(id: .local(UUID()), title: "Write report", projectID: fixture.project),
        )
        guard case let .local(taskLocalID) = created.id else {
            Issue.record("expected a local id while offline, got \(created.id)")
            return
        }
        let projectLocalID = try await fixture.store.read { db in
            try #require(try ProjectRecord.fetchAll(db).first { $0.accountID == fixture.accountID }).localID
        }
        let otherTaskRow = TaskRecord(
            localID: UUID(), accountID: fixture.accountID, remoteID: 6, title: "Outline", description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: projectLocalID, serverUpdatedAt: nil,
        )
        let relationRow = TaskRelationRecord(
            localID: UUID(), accountID: fixture.accountID, taskLocalID: taskLocalID, kind: .subtask,
            otherTaskRemoteID: 6, otherProjectRemoteID: 1, title: "Outline", isDone: false,
        )
        try await fixture.store.write { db in
            try otherTaskRow.insert(db)
            try relationRow.insert(db)
        }
        try await queueTaskRelationMutation(
            operation: .removeRelation, taskLocalID: taskLocalID, kind: .subtask,
            otherTaskLocalID: otherTaskRow.localID, in: fixture,
        )

        let task = try await fixture.repository.fetchTask(id: created.id)

        #expect(task.subtasks.isEmpty)
    }
}
