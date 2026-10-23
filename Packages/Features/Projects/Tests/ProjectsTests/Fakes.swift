@testable import Projects
import VikunjaCore

final class FakeCapabilityProvider: CapabilityProvider, @unchecked Sendable {
    var supportedFeatures: Set<VikunjaFeature> = []

    func serverInfo() async throws -> VikunjaServerInfo {
        VikunjaServerInfo(version: "0.24.6", caldavEnabled: false, totpEnabled: false, registrationEnabled: false)
    }

    func supports(_ feature: VikunjaFeature) async -> Bool {
        supportedFeatures.contains(feature)
    }
}

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var fetchError: VikunjaError?
    var createError: VikunjaError?
    var deleteError: VikunjaError?
    private(set) var createdProjects: [Project] = []
    private(set) var deletedIDs: [Int] = []

    func fetchProjects() async throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return projects
    }

    var fetchProjectError: VikunjaError?

    /// Falls back to a bare `Project(id: id)` when `projects` doesn't carry
    /// a matching entry, rather than throwing: most call sites set up
    /// `projects` to represent a project's *children* and never add the
    /// project under test itself, and `ProjectOverviewViewModel.load()`
    /// calls this for the viewed project on every load. Set
    /// `fetchProjectError` to simulate this call specifically failing.
    func fetchProject(id: Int) async throws -> Project {
        if let fetchProjectError {
            throw fetchProjectError
        }
        return projects.first(where: { $0.id == id }) ?? Project(id: id, title: "")
    }

    func create(_ project: Project) async throws -> Project {
        if let createError {
            throw createError
        }
        createdProjects.append(project)
        return project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        deletedIDs.append(id)
        projects.removeAll { $0.id == id }
    }
}

final class FakeFilterRepository: FilterRepositoryProtocol, @unchecked Sendable {
    var filter = SavedFilterDetail(id: 1, title: "", description: "", isFavorite: false, query: "")
    var fetchError: VikunjaError?
    var renameError: VikunjaError?
    var deleteError: VikunjaError?
    private(set) var renamedTitles: [String] = []
    private(set) var deletedIDs: [Int] = []

    func fetchFilter(id _: Int) async throws -> SavedFilterDetail {
        if let fetchError {
            throw fetchError
        }
        return filter
    }

    func renameFilter(id _: Int, title: String) async throws -> SavedFilterDetail {
        if let renameError {
            throw renameError
        }
        renamedTitles.append(title)
        filter = SavedFilterDetail(
            id: filter.id,
            title: title,
            description: filter.description,
            isFavorite: filter.isFavorite,
            query: filter.query,
        )
        return filter
    }

    func deleteFilter(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        deletedIDs.append(id)
    }
}

final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var fetchError: VikunjaError?
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    private(set) var updatedTasks: [VikunjaTask] = []

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        if let fetchError {
            throw fetchError
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let updateError {
            throw updateError
        }
        updatedTasks.append(task)
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
        return task
    }

    func delete(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

final class FakeLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    var labels: [Label] = []
    var addedLabelIDs: [(labelID: Int, taskID: Int)] = []
    var removedLabelIDs: [(labelID: Int, taskID: Int)] = []
    var addError: VikunjaError?
    var removeError: VikunjaError?

    func fetchLabels() async throws -> [Label] {
        labels
    }

    func create(_ label: Label) async throws -> Label {
        label
    }

    func update(_ label: Label) async throws -> Label {
        label
    }

    func delete(id: Int) async throws {
        labels.removeAll { $0.id == id }
    }

    func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        if let addError {
            throw addError
        }
        addedLabelIDs.append((labelID, taskID))
    }

    func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        if let removeError {
            throw removeError
        }
        removedLabelIDs.append((labelID, taskID))
    }
}

final class FakeTaskRelationRepository: TaskRelationRepositoryProtocol, @unchecked Sendable {
    struct RecordedRelation: Sendable {
        let kind: RelationKind
        let otherTaskID: Int
        let taskID: Int
    }

    var addedRelations: [RecordedRelation] = []
    var addError: VikunjaError?

    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        if let addError {
            throw addError
        }
        addedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }

    func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {}
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

@MainActor
final class FakeQuickAddContext: QuickAddContextTracking {
    private(set) var scopes: [Project] = []
    var preselectedProjectID: Int? {
        scopes.last?.id
    }

    var preselectedProject: Project? {
        scopes.last
    }

    func enterProjectScope(_ project: Project) {
        scopes.append(project)
    }

    func exitProjectScope(_ projectID: Int) {
        if let index = scopes.lastIndex(where: { $0.id == projectID }) {
            scopes.remove(at: index)
        }
    }
}

@MainActor
final class FakeTaskChangeBroadcaster: TaskChangeBroadcasting {
    private(set) var lastCreatedTask: TaskCreatedEvent?

    func taskCreated(projectID: Int) {
        lastCreatedTask = TaskCreatedEvent(projectID: projectID)
    }
}

@MainActor
final class FakeTaskSortStore: TaskSortStore, @unchecked Sendable {
    private(set) var taskSort: TaskSort = .init(field: .dueDate, direction: .ascending)

    func setTaskSort(_ sort: TaskSort) {
        taskSort = sort
    }
}
