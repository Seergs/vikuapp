import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

struct SyncEngineDrainTests {
    private let accountID = UUID()

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @discardableResult
    private func insertProject(
        in store: LocalStore,
        localID: UUID = UUID(),
        remoteID: Int?,
        title: String = "Groceries",
        parentProjectLocalID: UUID? = nil,
        serverUpdatedAt: Date? = nil,
    ) async throws -> ProjectRecord {
        let row = ProjectRecord(
            localID: localID, accountID: accountID, remoteID: remoteID, title: title, description: nil,
            isArchived: false, isFavorite: false, parentProjectLocalID: parentProjectLocalID,
            position: 0, hexColor: "", serverUpdatedAt: serverUpdatedAt,
        )
        try await store.write { db in try row.insert(db) }
        return row
    }

    @discardableResult
    private func insertLabel(
        in store: LocalStore,
        localID: UUID = UUID(),
        remoteID: Int?,
        title: String = "Urgent",
    ) async throws -> LabelRecord {
        let row = LabelRecord(localID: localID, accountID: accountID, remoteID: remoteID, title: title, hexColor: "")
        try await store.write { db in try row.insert(db) }
        return row
    }

    @discardableResult
    private func insertTask(
        in store: LocalStore,
        localID: UUID = UUID(),
        remoteID: Int?,
        title: String = "Buy milk",
        projectLocalID: UUID,
        serverUpdatedAt: Date? = nil,
    ) async throws -> TaskRecord {
        let row = TaskRecord(
            localID: localID, accountID: accountID, remoteID: remoteID, title: title, description: nil,
            isDone: false, dueDate: nil, priority: 0, projectLocalID: projectLocalID, serverUpdatedAt: serverUpdatedAt,
        )
        try await store.write { db in try row.insert(db) }
        return row
    }

    @discardableResult
    private func queueMutation(
        in store: LocalStore,
        entityType: MutationEntityType = .project,
        operation: MutationOperation,
        targetLocalID: UUID,
        payload: Encodable?,
        status: MutationStatus = .pending,
    ) async throws -> MutationQueueRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadString = try payload.flatMap { try String(bytes: encoder.encode($0), encoding: .utf8) }
        return try await store.write { db in
            var item = MutationQueueRecord(
                id: nil, accountID: accountID, entityType: entityType, operation: operation,
                targetLocalID: targetLocalID, payload: payloadString, createdAt: Date(), retryCount: 0,
                lastError: nil, status: status, needsConflictResolution: false,
            )
            try item.insert(db)
            return item
        }
    }

    @Test
    func `drain creates a project queued while offline and resolves its remote id locally`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let localID = UUID()
        try await insertProject(in: store, localID: localID, remoteID: nil, title: "Groceries")
        try await queueMutation(
            in: store, operation: .create, targetLocalID: localID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Groceries", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "ff0000", baseUpdatedAt: nil,
            ),
        )

        try await engine.drainProjectMutations()

        #expect(repository.createdProjects.count == 1)
        let fetched = try await store.read { db in try ProjectRecord.fetchOne(db, key: localID) }
        let row = try #require(fetched)
        #expect(row.remoteID != nil)
        #expect(row.serverUpdatedAt != nil)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain defers a childs create until its locally created parent has synced`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.createError = VikunjaError.network("offline")
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let parentLocalID = UUID()
        let childLocalID = UUID()
        try await insertProject(in: store, localID: parentLocalID, remoteID: nil, title: "Parent")
        try await insertProject(in: store, localID: childLocalID, remoteID: nil, title: "Child")
        try await queueMutation(
            in: store, operation: .create, targetLocalID: parentLocalID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Parent", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )
        try await queueMutation(
            in: store, operation: .create, targetLocalID: childLocalID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Child", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: parentLocalID, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )

        try await engine.drainProjectMutations()

        // The parent's own create failed, so the child's create must never
        // have been attempted — it would otherwise reference a parent the
        // server has never heard of.
        #expect(repository.createdProjects.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.count == 2)
    }

    @Test
    func `drain creates a parent then its child in the same pass once the parent succeeds`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let parentLocalID = UUID()
        let childLocalID = UUID()
        try await insertProject(in: store, localID: parentLocalID, remoteID: nil, title: "Parent")
        // Whoever enqueues a child's create sets its local parent link up
        // front, the same way the queued payload below carries it — drain
        // only has to resolve `remoteID`/`serverUpdatedAt`, never the local
        // hierarchy, which was already correct the moment this row was
        // created.
        try await insertProject(
            in: store, localID: childLocalID, remoteID: nil, title: "Child", parentProjectLocalID: parentLocalID,
        )
        try await queueMutation(
            in: store, operation: .create, targetLocalID: parentLocalID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Parent", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )
        try await queueMutation(
            in: store, operation: .create, targetLocalID: childLocalID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Child", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: parentLocalID, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )

        try await engine.drainProjectMutations()

        #expect(repository.createdProjects.count == 2)
        let fetchedChild = try await store.read { db in try ProjectRecord.fetchOne(db, key: childLocalID) }
        let fetchedParent = try await store.read { db in try ProjectRecord.fetchOne(db, key: parentLocalID) }
        let childRow = try #require(fetchedChild)
        let parentRow = try #require(fetchedParent)
        #expect(childRow.parentProjectLocalID == parentLocalID)
        #expect(parentRow.remoteID != nil)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain pushes an update and clears the queue item on success`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let localID = UUID()
        try await insertProject(in: store, localID: localID, remoteID: 1, title: "Groceries")
        try await queueMutation(
            in: store, operation: .update, targetLocalID: localID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Groceries (renamed)", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )

        try await engine.drainProjectMutations()

        #expect(repository.updatedProjects.map(\.title) == ["Groceries (renamed)"])
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain flags a conflict instead of overwriting a newer server side edit`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let localID = UUID()
        let queuedAt = Date(timeIntervalSince1970: 1000)
        let observedByLaterPull = Date(timeIntervalSince1970: 2000)
        try await insertProject(in: store, localID: localID, remoteID: 1, serverUpdatedAt: observedByLaterPull)
        // What the server actually has right now - the edit that conflicts
        // with the queued mutation below.
        repository.projects = [Project(id: 1, title: "Groceries (edited elsewhere)", updated: observedByLaterPull)]
        try await queueMutation(
            in: store, operation: .update, targetLocalID: localID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Groceries (renamed)", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: queuedAt,
            ),
        )

        try await engine.drainProjectMutations()

        #expect(repository.updatedProjects.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.count == 1)
        #expect(remaining[0].needsConflictResolution == true)
        #expect(remaining[0].status == .pending)
        // The conflict no longer protects the row, so the same pass that
        // flagged it also resyncs its content to the server's real state -
        // never left showing the discarded local edit.
        let row = try await store.read { db in try #require(try ProjectRecord.fetchOne(db, key: localID)) }
        #expect(row.title == "Groceries (edited elsewhere)")
    }

    @Test
    func `drain skips a conflicted item on a later pass until it is resolved`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let localID = UUID()
        try await insertProject(
            in: store, localID: localID, remoteID: 1, serverUpdatedAt: Date(timeIntervalSince1970: 2000),
        )
        try await queueMutation(
            in: store, operation: .update, targetLocalID: localID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Groceries (renamed)", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: Date(timeIntervalSince1970: 1000),
            ),
        )
        try await engine.drainProjectMutations()

        try await engine.drainProjectMutations()

        #expect(repository.updatedProjects.isEmpty)
    }

    @Test
    func `drain deletes a project and removes the local row on success`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let localID = UUID()
        try await insertProject(in: store, localID: localID, remoteID: 1)
        try await queueMutation(
            in: store, operation: .delete, targetLocalID: localID,
            payload: ProjectDeletePayload(remoteID: 1),
        )

        try await engine.drainProjectMutations()

        #expect(repository.deletedIDs == [1])
        let rows = try await store.read { db in try ProjectRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain marks an item failed and increments its retry count rather than stopping the whole pass`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.updateError = VikunjaError.network("boom")
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let failingLocalID = UUID()
        let okLocalID = UUID()
        try await insertProject(in: store, localID: failingLocalID, remoteID: 1, title: "Will fail")
        try await insertProject(in: store, localID: okLocalID, remoteID: nil, title: "Will succeed")
        try await queueMutation(
            in: store, operation: .update, targetLocalID: failingLocalID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Will fail", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )
        try await queueMutation(
            in: store, operation: .create, targetLocalID: okLocalID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Will succeed", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )

        try await engine.drainProjectMutations()

        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.count == 1)
        #expect(remaining[0].targetLocalID == failingLocalID)
        #expect(remaining[0].status == .failed)
        #expect(remaining[0].retryCount == 1)
        #expect(remaining[0].lastError != nil)
        #expect(repository.createdProjects.count == 1)
    }

    @Test
    func `a failed item is retried on the very next drain pass, not stuck forever`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let repository = FakeProjectRepository()
        repository.createError = VikunjaError.unauthorized
        let engine = SyncEngine(
            localStore: store, projectRepository: repository,
            labelRepository: FakeLabelRepository(), taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let localID = UUID()
        try await insertProject(in: store, localID: localID, remoteID: nil, title: "Groceries")
        try await queueMutation(
            in: store, operation: .create, targetLocalID: localID,
            payload: ProjectCreateOrUpdatePayload(
                title: "Groceries", description: nil, isArchived: false, isFavorite: false,
                parentProjectLocalID: nil, position: 0, hexColor: "", baseUpdatedAt: nil,
            ),
        )

        try await engine.drainProjectMutations() // fails - token still bad
        let afterFirstDrain = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(afterFirstDrain[0].status == .failed)
        #expect(repository.createdProjects.isEmpty)

        repository.createError = nil // credential fixed, same as reconnecting with a valid token
        try await engine.drainProjectMutations()

        let afterSecondDrain = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(afterSecondDrain.isEmpty)
        #expect(repository.createdProjects.count == 1)
    }

    @Test
    func `drain creates a label queued while offline and resolves its remote id locally`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let labelRepository = FakeLabelRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let localID = UUID()
        try await insertLabel(in: store, localID: localID, remoteID: nil, title: "Urgent")
        try await queueMutation(
            in: store, entityType: .label, operation: .create, targetLocalID: localID,
            payload: LabelCreateOrUpdatePayload(title: "Urgent", hexColor: "ff0000"),
        )

        try await engine.drainLabelMutations()

        #expect(labelRepository.createdLabels.map(\.title) == ["Urgent"])
        let row = try await store.read { db in try #require(try LabelRecord.fetchOne(db, key: localID)) }
        #expect(row.remoteID != nil)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain pushes a label update and clears the queue item on success`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let labelRepository = FakeLabelRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let localID = UUID()
        try await insertLabel(in: store, localID: localID, remoteID: 1, title: "Urgent")
        try await queueMutation(
            in: store, entityType: .label, operation: .update, targetLocalID: localID,
            payload: LabelCreateOrUpdatePayload(title: "Urgent (renamed)", hexColor: "ff0000"),
        )

        try await engine.drainLabelMutations()

        #expect(labelRepository.updatedLabels.map(\.title) == ["Urgent (renamed)"])
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain deletes a label and removes the local row on success`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let labelRepository = FakeLabelRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let localID = UUID()
        try await insertLabel(in: store, localID: localID, remoteID: 1, title: "Urgent")
        try await queueMutation(
            in: store, entityType: .label, operation: .delete, targetLocalID: localID,
            payload: LabelDeletePayload(remoteID: 1),
        )

        try await engine.drainLabelMutations()

        #expect(labelRepository.deletedIDs == [1])
        let rows = try await store.read { db in try LabelRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain marks a failed label mutation and retries it on the next pass`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let labelRepository = FakeLabelRepository()
        labelRepository.createError = VikunjaError.unauthorized
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository, taskRepository: FakeTaskRepository(),

            accountID: accountID,
        )
        let localID = UUID()
        try await insertLabel(in: store, localID: localID, remoteID: nil, title: "Urgent")
        try await queueMutation(
            in: store, entityType: .label, operation: .create, targetLocalID: localID,
            payload: LabelCreateOrUpdatePayload(title: "Urgent", hexColor: "ff0000"),
        )

        try await engine.drainLabelMutations()
        let afterFirstDrain = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(afterFirstDrain[0].status == .failed)

        labelRepository.createError = nil
        try await engine.drainLabelMutations()

        let afterSecondDrain = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(afterSecondDrain.isEmpty)
        #expect(labelRepository.createdLabels.count == 1)
    }

    @Test
    func `drain creates a task queued while offline and resolves its remote id locally`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let taskRepository = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: taskRepository, accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let localID = UUID()
        try await insertTask(
            in: store, localID: localID, remoteID: nil, title: "Buy milk", projectLocalID: projectLocalID,
        )
        try await queueMutation(
            in: store, entityType: .task, operation: .create, targetLocalID: localID,
            payload: TaskCreateOrUpdatePayload(
                title: "Buy milk", description: nil, isDone: false, dueDate: nil, priority: 0,
                projectLocalID: projectLocalID, baseUpdatedAt: nil,
            ),
        )

        try await engine.drainTaskMutations()

        #expect(taskRepository.createdTasks.map(\.title) == ["Buy milk"])
        let row = try await store.read { db in try #require(try TaskRecord.fetchOne(db, key: localID)) }
        #expect(row.remoteID != nil)
        #expect(row.serverUpdatedAt != nil)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain defers a tasks create until its locally created project has synced`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let taskRepository = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: taskRepository, accountID: accountID,
        )
        // The project this task belongs to was also created offline and
        // hasn't synced - its own create isn't even queued in this test, so
        // it stays unresolved for every drain pass.
        let projectLocalID = try await insertProject(in: store, remoteID: nil).localID
        let localID = UUID()
        try await insertTask(in: store, localID: localID, remoteID: nil, projectLocalID: projectLocalID)
        try await queueMutation(
            in: store, entityType: .task, operation: .create, targetLocalID: localID,
            payload: TaskCreateOrUpdatePayload(
                title: "Buy milk", description: nil, isDone: false, dueDate: nil, priority: 0,
                projectLocalID: projectLocalID, baseUpdatedAt: nil,
            ),
        )

        try await engine.drainTaskMutations()

        #expect(taskRepository.createdTasks.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.count == 1)
    }

    @Test
    func `drain pushes a task update and clears the queue item on success`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let taskRepository = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: taskRepository, accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let localID = UUID()
        try await insertTask(in: store, localID: localID, remoteID: 10, projectLocalID: projectLocalID)
        try await queueMutation(
            in: store, entityType: .task, operation: .update, targetLocalID: localID,
            payload: TaskCreateOrUpdatePayload(
                title: "Buy milk and eggs", description: nil, isDone: false, dueDate: nil, priority: 0,
                projectLocalID: projectLocalID, baseUpdatedAt: nil,
            ),
        )

        try await engine.drainTaskMutations()

        #expect(taskRepository.updatedTasks.map(\.title) == ["Buy milk and eggs"])
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain flags a task conflict instead of overwriting a newer server side edit`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let taskRepository = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: taskRepository, accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let localID = UUID()
        let queuedAt = Date(timeIntervalSince1970: 1000)
        let observedByLaterPull = Date(timeIntervalSince1970: 2000)
        try await insertTask(
            in: store, localID: localID, remoteID: 10, projectLocalID: projectLocalID,
            serverUpdatedAt: observedByLaterPull,
        )
        // What the server actually has right now - the edit that conflicts
        // with the queued mutation below.
        taskRepository.tasks = [
            VikunjaTask(id: 10, title: "Buy milk (edited elsewhere)", projectID: 1, updated: observedByLaterPull),
        ]
        try await queueMutation(
            in: store, entityType: .task, operation: .update, targetLocalID: localID,
            payload: TaskCreateOrUpdatePayload(
                title: "Buy milk and eggs", description: nil, isDone: false, dueDate: nil, priority: 0,
                projectLocalID: projectLocalID, baseUpdatedAt: queuedAt,
            ),
        )

        try await engine.drainTaskMutations()

        #expect(taskRepository.updatedTasks.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.count == 1)
        #expect(remaining[0].needsConflictResolution == true)
        #expect(remaining[0].status == .pending)
        // The conflict no longer protects the row, so the same pass that
        // flagged it also resyncs its content to the server's real state.
        let row = try await store.read { db in try #require(try TaskRecord.fetchOne(db, key: localID)) }
        #expect(row.title == "Buy milk (edited elsewhere)")
    }

    @Test
    func `drain deletes a task and removes the local row on success`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let taskRepository = FakeTaskRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: taskRepository, accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let localID = UUID()
        try await insertTask(in: store, localID: localID, remoteID: 10, projectLocalID: projectLocalID)
        try await queueMutation(
            in: store, entityType: .task, operation: .delete, targetLocalID: localID,
            payload: TaskDeletePayload(remoteID: 10),
        )

        try await engine.drainTaskMutations()

        #expect(taskRepository.deletedIDs == [10])
        let rows = try await store.read { db in try TaskRecord.fetchAll(db) }
        #expect(rows.isEmpty)
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain marks a failed task mutation and retries it on the next pass`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let taskRepository = FakeTaskRepository()
        taskRepository.createError = VikunjaError.unauthorized
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: taskRepository, accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let localID = UUID()
        try await insertTask(in: store, localID: localID, remoteID: nil, projectLocalID: projectLocalID)
        try await queueMutation(
            in: store, entityType: .task, operation: .create, targetLocalID: localID,
            payload: TaskCreateOrUpdatePayload(
                title: "Buy milk", description: nil, isDone: false, dueDate: nil, priority: 0,
                projectLocalID: projectLocalID, baseUpdatedAt: nil,
            ),
        )

        try await engine.drainTaskMutations()
        let afterFirstDrain = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(afterFirstDrain[0].status == .failed)

        taskRepository.createError = nil
        try await engine.drainTaskMutations()

        let afterSecondDrain = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(afterSecondDrain.isEmpty)
        #expect(taskRepository.createdTasks.count == 1)
    }

    @Test
    func `drain pushes a queued addLabel once the task and the label have both synced`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let labelRepository = FakeLabelRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: labelRepository,
            taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let taskLocalID = try await insertTask(in: store, remoteID: 10, projectLocalID: projectLocalID).localID
        let labelLocalID = try await insertLabel(in: store, remoteID: 20).localID
        try await queueMutation(
            in: store, entityType: .task, operation: .addLabel, targetLocalID: taskLocalID,
            payload: TaskLabelMutationPayload(labelLocalID: labelLocalID),
        )

        try await engine.drainTaskMutations()

        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [.remote(20)])
        #expect(labelRepository.addedLabelIDs.map(\.taskID) == [.remote(10)])
        let taskRow = try #require(try await store.read { db in try TaskRecord.fetchOne(db, key: taskLocalID) })
        #expect(taskRow.labelRemoteIDs == "20")
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }

    @Test
    func `drain defers a queued addLabel until a locally created label has synced`() async throws {
        let store = try LocalStore(directory: temporaryDirectory())
        let labelRepository = FakeLabelRepository()
        let engine = SyncEngine(
            localStore: store, projectRepository: FakeProjectRepository(), labelRepository: labelRepository,
            taskRepository: FakeTaskRepository(), accountID: accountID,
        )
        let projectLocalID = try await insertProject(in: store, remoteID: 1).localID
        let taskLocalID = try await insertTask(in: store, remoteID: 10, projectLocalID: projectLocalID).localID
        let labelLocalID = try await insertLabel(in: store, remoteID: nil).localID
        try await queueMutation(
            in: store, entityType: .task, operation: .addLabel, targetLocalID: taskLocalID,
            payload: TaskLabelMutationPayload(labelLocalID: labelLocalID),
        )

        try await engine.drainTaskMutations()

        #expect(labelRepository.addedLabelIDs.isEmpty)
        let stillQueued = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(stillQueued.count == 1)
        #expect(stillQueued[0].status == .pending)

        // The label's own create resolves (as if its queue item had drained
        // in the same pass, or on an earlier one) - the deferred addLabel
        // should push through on the very next pass.
        try await store.write { db in
            var labelRow = try #require(try LabelRecord.fetchOne(db, key: labelLocalID))
            labelRow.remoteID = 20
            try labelRow.save(db)
        }
        try await engine.drainTaskMutations()

        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [.remote(20)])
        let remaining = try await store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(remaining.isEmpty)
    }
}
