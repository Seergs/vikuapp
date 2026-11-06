@testable import Home
import VikunjaCore

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var fetchError: VikunjaError?

    func fetchProjects() async throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return projects
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id: EntityID) async throws {
        projects.removeAll { $0.id == id }
    }
}

final class FakeTaskRepository: TaskRepositoryProtocol, TaskBulkCompletionRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var failingDeleteIDs: Set<EntityID> = []
    private(set) var deletedTaskIDs: [EntityID] = []
    var fetchError: VikunjaError?
    /// Project ids whose `fetchTasks` call fails, independent of `fetchError`
    /// — for testing that one project's failure doesn't take down the whole
    /// Today screen.
    var failingProjectIDs: Set<Int> = []
    var updateError: VikunjaError?
    var beforeUpdate: (@Sendable () async -> Void)?

    var completionError: Error?
    var beforeCompletion: (@Sendable () async throws -> Void)?
    private(set) var completionCalls: [(ids: [EntityID], isDone: Bool)] = []

    func setCompletion(taskIDs: [EntityID], isDone: Bool) async throws -> [VikunjaTask] {
        completionCalls.append((taskIDs, isDone))
        try await beforeCompletion?()
        if let completionError {
            throw completionError
        }
        var result: [VikunjaTask] = []
        for id in taskIDs {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw VikunjaError.notFound }
            tasks[index].isDone = isDone
            result.append(tasks[index])
        }
        return result
    }

    func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        if let fetchError {
            throw fetchError
        }
        if let remoteProjectID = projectID.remoteValue, failingProjectIDs.contains(remoteProjectID) {
            throw VikunjaError.network("offline")
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: EntityID) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        await beforeUpdate?()
        if let updateError {
            throw updateError
        }
        return task
    }

    func delete(id: EntityID) async throws {
        if failingDeleteIDs.contains(id) {
            throw VikunjaError.network("rejected")
        }
        deletedTaskIDs.append(id)
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

final class FakeLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    var labels: [Label] = []
    var addedLabelIDs: [(labelID: EntityID, taskID: EntityID)] = []
    var removedLabelIDs: [(labelID: EntityID, taskID: EntityID)] = []
    var addError: VikunjaError?
    var removeError: VikunjaError?

    func fetchLabels() async throws -> [Label] {
        labels
    }

    func create(_ label: Label) async throws -> Label {
        labels.append(label)
        return label
    }

    func update(_ label: Label) async throws -> Label {
        label
    }

    func delete(id: EntityID) async throws {
        labels.removeAll { $0.id == id }
    }

    func addLabel(_ labelID: EntityID, toTask taskID: EntityID) async throws {
        if let addError {
            throw addError
        }
        addedLabelIDs.append((labelID, taskID))
    }

    func removeLabel(_ labelID: EntityID, fromTask taskID: EntityID) async throws {
        if let removeError {
            throw removeError
        }
        removedLabelIDs.append((labelID, taskID))
    }
}

final class FakeTaskRelationRepository: TaskRelationRepositoryProtocol, @unchecked Sendable {
    struct RecordedRelation: Sendable {
        let kind: RelationKind
        let otherTaskID: EntityID
        let taskID: EntityID
    }

    var addedRelations: [RecordedRelation] = []
    var addError: VikunjaError?

    func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws {
        if let addError {
            throw addError
        }
        addedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }

    func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws {}
}

final class FakeToastPresenter: ToastPresenting, @unchecked Sendable {
    private(set) var shownMessages: [(message: String, style: ToastStyle)] = []

    func show(_ message: String, style: ToastStyle) {
        shownMessages.append((message, style))
    }
}

final class FakeHapticPresenter: HapticFeedbackPresenting, @unchecked Sendable {
    private(set) var played: [HapticStyle] = []

    func play(_ style: HapticStyle) {
        played.append(style)
    }
}

final class FakeHomeSelectionCaching: HomeSelectionCaching, @unchecked Sendable {
    private(set) var cached: CachedHomeSelection?
    private(set) var setCallCount = 0

    init(cached: CachedHomeSelection? = nil) {
        self.cached = cached
    }

    func cachedHomeSelection() -> CachedHomeSelection? {
        cached
    }

    func setCachedHomeSelection(_ selection: CachedHomeSelection?) {
        setCallCount += 1
        cached = selection
    }
}
