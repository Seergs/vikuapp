import Foundation
import Testing
import VikunjaCore
@testable import VikunjaPersistence

/// Guards a bug reproduced with the real networking adapters and a
/// disposable Vikunja 2.8.0 server. See docs/investigations/task-subresource-conflicts.md.
struct TaskEditConflictTests {
    enum Subresource: Sendable, CaseIterable {
        case label
        case comment
    }

    private struct Fixture {
        let directory: URL
        let store: LocalStore
        let accountID: UUID
        let engine: SyncEngine
        let tasks: OfflineTaskRepository
        let labels: OfflineLabelRepository
        let comments: OfflineTaskCommentRepository
        let network: FakeTaskRepository
        let originalDate = Date(timeIntervalSince1970: 1000)
        let subresourceDate = Date(timeIntervalSince1970: 1003)

        init() throws {
            self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.store = try LocalStore(directory: directory)
            self.accountID = UUID()
            let projects = FakeProjectRepository()
            projects.projects = [Project(id: 1, title: "Investigation")]
            let network = FakeTaskRepository()
            self.network = network
            network.tasks = [VikunjaTask(id: 10, title: "Test task", projectID: 1, updated: originalDate)]
            let labelNetwork = FakeLabelRepository()
            let label = Label(id: 20, title: "Test label", hexColor: "")
            labelNetwork.labels = [label]
            let commentNetwork = FakeTaskCommentRepository()
            let updated = subresourceDate
            // Measured server behavior: both operations advance the owning task's
            // updated timestamp, but neither response returns the updated task.
            labelNetwork.onAddLabel = {
                network.tasks[0].labels = [label]
                network.tasks[0].updated = updated
            }
            commentNetwork.onAddComment = { network.tasks[0].updated = updated }
            self.engine = SyncEngine(
                localStore: store, projectRepository: projects, labelRepository: labelNetwork,
                taskRepository: network, relationRepository: FakeTaskRelationRepository(),
                taskBulkUpdateRepository: network, commentRepository: commentNetwork, accountID: accountID,
            )
            self.tasks = OfflineTaskRepository(
                localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
            )
            self.labels = OfflineLabelRepository(
                localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
            )
            self.comments = OfflineTaskCommentRepository(
                localStore: store, accountID: accountID, syncRequester: NoopKanbanSyncRequester(),
            )
        }

        func add(_ subresource: Subresource) async throws {
            switch subresource {
            case .label: try await labels.addLabel(20, toTask: 10)
            case .comment: _ = try await comments.addComment("Test comment", toTask: 10)
            }
            try await engine.synchronize()
            #expect(try await store.pendingSyncOperations(accountID: accountID).isEmpty)
            #expect(network.tasks[0].updated == subresourceDate)
            #expect(try await tasks.fetchTask(id: 10).updated == originalDate)
        }

        func queuePriority() async throws {
            var task = try await tasks.fetchTask(id: 10)
            task.priority = .high
            _ = try await tasks.update(task)
        }
    }

    @Test(arguments: Subresource.allCases)
    func `acknowledged subresource then priority synchronizes`(_ subresource: Subresource) async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.add(subresource)
        try await fixture.queuePriority()

        // The next normal account pass pulls before draining the queued edit.
        try await fixture.engine.synchronize()
        let operations = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(operations.isEmpty)
        #expect(fixture.network.updatedTasks.count == 1)
        #expect(fixture.network.tasks[0].priority == .high)
        if subresource == .label {
            #expect(fixture.network.tasks[0].labels.map(\.id) == [20])
        }
    }

    @Test(arguments: Subresource.allCases)
    func `refresh before editing avoids subresource conflict`(_ subresource: Subresource) async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.add(subresource)
        // Control: an extra pull before the edit makes the queued baseline current.
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        try await fixture.engine.synchronize()
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
        #expect(fixture.network.tasks[0].priority == .high)
        #expect(fixture.network.updatedTasks.count == 1)
    }

    @Test
    func `priority without subresource write synchronizes`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        try await fixture.engine.synchronize()
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
        #expect(fixture.network.tasks[0].priority == .high)
    }

    @Test(arguments: Subresource.allCases, [false, true])
    func `subresource writes do not block bulk completion or due dates`(
        _ subresource: Subresource, reschedule: Bool,
    ) async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.add(subresource)
        if reschedule {
            _ = try await fixture.tasks.setDueDate(taskIDs: [10], dueDate: Date(timeIntervalSince1970: 5000))
        } else {
            _ = try await fixture.tasks.setCompletion(taskIDs: [10], isDone: true)
        }
        try await fixture.engine.synchronize()
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
        #expect(fixture.network.bulkUpdateCalls.count == 1)
        #expect(reschedule ? fixture.network.tasks[0].dueDate != nil : fixture.network.tasks[0].isDone)
    }

    @Test(arguments: ["title", "description", "completion", "dueDate", "priority", "reminders", "project"])
    func `external core changes remain conflicts even within the same timestamp`(_ field: String) async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        switch field {
        case "title": fixture.network.tasks[0].title = "Edited elsewhere"
        case "description": fixture.network.tasks[0].description = "Edited elsewhere"
        case "completion": fixture.network.tasks[0].isDone = true
        case "dueDate": fixture.network.tasks[0].dueDate = Date(timeIntervalSince1970: 5000)
        case "priority": fixture.network.tasks[0].priority = .urgent
        case "reminders": fixture.network.tasks[0].reminders = [TaskReminder(reminder: .distantFuture)]
        default: fixture.network.tasks[0].projectID = 2
        }
        try await fixture.engine.drainTaskMutations()
        let operations = try await fixture.store.pendingSyncOperations(accountID: fixture.accountID)
        #expect(operations.count == 1)
        #expect(operations.first?.needsConflictResolution == true)
        #expect(fixture.network.updatedTasks.isEmpty)
    }

    @Test
    func `pulls and coalescing preserve the original base instead of optimistic local fields`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        fixture.network.tasks[0].title = "External title"
        fixture.network.tasks[0].updated = fixture.subresourceDate
        try await fixture.engine.pullTasks()
        var edited = try await fixture.tasks.fetchTask(id: 10)
        edited.description = "Second local edit"
        _ = try await fixture.tasks.update(edited)
        let items = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        let item = try #require(items.first)
        let payload = try KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: item)
        #expect(items.count == 1)
        #expect(payload.baseFields?.priority == VikunjaTask.Priority.unset.rawValue)
        #expect(payload.baseFields?.title == "Test task")
        #expect(payload.baseFields?.description.isEmpty == true)
        #expect(payload.baseUpdatedAt == fixture.originalDate)
        #expect(item.baseUpdatedAt == fixture.originalDate)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.updatedTasks.isEmpty)
    }

    @Test
    func `a newer edit during upload uses the acknowledged server task as its base`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        fixture.network.beforeUpdateResponse = {
            var edited = try await fixture.tasks.fetchTask(id: 10)
            edited.title = "Edited during upload"
            _ = try await fixture.tasks.update(edited)
        }
        try await fixture.engine.drainTaskMutations()
        let queued = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        let payload = try KanbanLocalMutations.decode(
            TaskCreateOrUpdatePayload.self, item: #require(queued.first),
        )
        #expect(payload.baseFields?.priority == VikunjaTask.Priority.high.rawValue)
        #expect(payload.baseFields?.title == "Test task")
        #expect(payload.title == "Edited during upload")
        fixture.network.beforeUpdateResponse = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.tasks[0].title == "Edited during upload")
        #expect(fixture.network.tasks[0].priority == .high)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test
    func `a lost response is acknowledged on retry when the desired fields are already on the server`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        fixture.network.beforeUpdateResponse = { throw VikunjaError.timeout }
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).first?.status == .failed)
        fixture.network.beforeUpdateResponse = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.updatedTasks.count == 1)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test(arguments: [false, true])
    func `offline or cancelled verification retains the queued edit for reconnection`(_ cancelled: Bool) async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.queuePriority()
        fixture.network.fetchTaskError = cancelled ? CancellationError() : VikunjaError.offline
        do {
            try await fixture.engine.drainTaskMutations()
            Issue.record("Expected verification to be interrupted")
        } catch {
            #expect(cancelled ? error is CancellationError : (error as? VikunjaError) == .offline)
        }
        let items = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(items.count == 1)
        #expect(items[0].status == .pending && items[0].retryCount == 0)
        #expect(try await fixture.tasks.fetchTask(id: 10).priority == .high)
        fixture.network.fetchTaskError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.tasks[0].priority == .high)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test
    func `pending snapshots survive reopening the store after a subresource write`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        try await fixture.add(.label)
        try await fixture.queuePriority()
        let reopened = try LocalStore(directory: fixture.directory)
        let engine = SyncEngine(
            localStore: reopened, projectRepository: FakeProjectRepository(), labelRepository: FakeLabelRepository(),
            taskRepository: fixture.network, relationRepository: FakeTaskRelationRepository(),
            accountID: fixture.accountID,
        )
        try await engine.drainTaskMutations()
        #expect(fixture.network.tasks[0].priority == .high)
        #expect(try await reopened.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test
    func `a full edit replacing pending completion retains the server base`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        _ = try await fixture.tasks.setCompletion(taskIDs: [10], isDone: true)
        var task = try await fixture.tasks.fetchTask(id: 10)
        task.isDone = false
        task.priority = .high
        _ = try await fixture.tasks.update(task)
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.tasks[0].priority == .high)
        #expect(!fixture.network.tasks[0].isDone)
        #expect(fixture.network.bulkUpdateCalls.isEmpty)
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test
    func `server normalized fields become the cached base for the next edit`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        var task = try await fixture.tasks.fetchTask(id: 10)
        task.description = "<p>Clean</p><script>discarded</script>"
        _ = try await fixture.tasks.update(task)
        var normalized = fixture.network.tasks[0]
        normalized.description = "<p>Clean</p>"
        fixture.network.updateResponse = normalized
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.tasks.fetchTask(id: 10).description == "<p>Clean</p>")
        fixture.network.updateResponse = nil
        try await fixture.queuePriority()
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.tasks[0].priority == .high)
        #expect(fixture.network.tasks[0].description == "<p>Clean</p>")
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func `bulk verification releases claims on offline or cancelled reads`(
        _ cancelled: Bool, reschedule: Bool,
    ) async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        if reschedule {
            _ = try await fixture.tasks.setDueDate(taskIDs: [10], dueDate: Date(timeIntervalSince1970: 5000))
        } else {
            _ = try await fixture.tasks.setCompletion(taskIDs: [10], isDone: true)
        }
        fixture.network.fetchTaskError = cancelled ? CancellationError() : VikunjaError.offline
        do {
            try await fixture.engine.drainTaskMutations()
            Issue.record("Expected verification to be interrupted")
        } catch {
            #expect(cancelled ? error is CancellationError : (error as? VikunjaError) == .offline)
        }
        let items = try await fixture.store.read { db in try MutationQueueRecord.fetchAll(db) }
        #expect(items.count == 1)
        #expect(items[0].status == .pending && items[0].retryCount == 0)
        #expect(fixture.network.bulkUpdateCalls.isEmpty)
        fixture.network.fetchTaskError = nil
        try await fixture.engine.drainTaskMutations()
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }

    @Test
    func `an edit during offline task creation uses its first server response as the base`() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await fixture.engine.synchronize()
        let original = try await fixture.tasks.create(
            VikunjaTask(id: .local(UUID()), title: "Original offline task", projectID: 1),
        )
        fixture.network.beforeCreateResponse = {
            var edited = original
            edited.title = "Edited during creation"
            _ = try await fixture.tasks.update(edited)
        }
        try await fixture.engine.drainTaskMutations()
        fixture.network.beforeCreateResponse = nil
        try await fixture.engine.drainTaskMutations()
        #expect(fixture.network.createdTasks.count == 1)
        #expect(fixture.network.updatedTasks.last?.title == "Edited during creation")
        #expect(try await fixture.tasks.fetchTask(id: original.id).title == "Edited during creation")
        #expect(try await fixture.store.pendingSyncOperations(accountID: fixture.accountID).isEmpty)
    }
}
