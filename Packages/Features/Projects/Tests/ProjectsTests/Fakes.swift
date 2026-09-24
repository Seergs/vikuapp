@testable import Projects
import VikunjaCore

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

    func fetchProject(id: Int) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return project
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
        addedLabelIDs.append((labelID, taskID))
    }

    func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {}
}

final class FakeTaskRelationRepository: TaskRelationRepositoryProtocol, @unchecked Sendable {
    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {}
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
    private(set) var scopes: [Int] = []
    var preselectedProjectID: Int? {
        scopes.last
    }

    func enterProjectScope(_ projectID: Int) {
        scopes.append(projectID)
    }

    func exitProjectScope(_ projectID: Int) {
        if let index = scopes.lastIndex(of: projectID) {
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
