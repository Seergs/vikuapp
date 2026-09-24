import Foundation
import VikunjaCore

/// Fake repositories/presenters for `DuplicateTaskViewModelTests`. Mirrors
/// (a subset of) `Features/Tasks`' own `TasksTests/Fakes.swift` — kept
/// separate rather than shared across test targets since Swift Package
/// Manager test targets don't expose their sources to one another.
final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var fetchError: VikunjaError?
    var createError: VikunjaError?
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    var searchError: VikunjaError?
    var searchResults: [VikunjaTask] = []
    private var nextID = 1000

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        if let fetchError {
            throw fetchError
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        if let fetchError {
            throw fetchError
        }
        guard let task = tasks.first(where: { $0.id == id }) else {
            throw VikunjaError.notFound
        }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let createError {
            throw createError
        }
        // Mirrors the real API: the server assigns the id. Relations/labels
        // aren't accepted in the create body, so they're dropped here too.
        let created = VikunjaTask(
            id: nextID,
            title: task.title,
            description: task.description,
            isDone: task.isDone,
            dueDate: task.dueDate,
            priority: task.priority,
            projectID: task.projectID,
        )
        nextID += 1
        tasks.append(created)
        return created
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let updateError {
            throw updateError
        }
        return task
    }

    func delete(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query _: String) async throws -> [VikunjaTask] {
        if let searchError {
            throw searchError
        }
        return searchResults
    }
}

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var fetchError: VikunjaError?

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
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id: Int) async throws {
        projects.removeAll { $0.id == id }
    }
}

final class FakeLabelRepository: LabelRepositoryProtocol, @unchecked Sendable {
    var labels: [Label] = []
    var addedLabelIDs: [(labelID: Int, taskID: Int)] = []
    var removedLabelIDs: [(labelID: Int, taskID: Int)] = []
    var fetchError: VikunjaError?
    var createError: VikunjaError?
    var addError: VikunjaError?
    var removeError: VikunjaError?
    private var nextID = 100

    func fetchLabels() async throws -> [Label] {
        if let fetchError {
            throw fetchError
        }
        return labels
    }

    func create(_ label: Label) async throws -> Label {
        if let createError {
            throw createError
        }
        let created = Label(id: nextID, title: label.title, hexColor: label.hexColor)
        nextID += 1
        labels.append(created)
        return created
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
    var removedRelations: [RecordedRelation] = []
    var addError: VikunjaError?
    var removeError: VikunjaError?

    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        if let addError {
            throw addError
        }
        addedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }

    func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {
        if let removeError {
            throw removeError
        }
        removedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }
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
