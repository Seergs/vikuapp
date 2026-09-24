import Foundation
@testable import VikunjaCore

/// Fakes shared by `AccountTaskLoaderTests` and `TaskListMutatorTests`.
final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var fetchError: VikunjaError?
    /// Project ids whose `fetchTasks` call fails, independent of `fetchError`.
    var failingProjectIDs: Set<Int> = []
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    private(set) var updatedTasks: [VikunjaTask] = []
    private(set) var deletedIDs: [Int] = []

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        if let fetchError {
            throw fetchError
        }
        if failingProjectIDs.contains(projectID) {
            throw VikunjaError.network("offline")
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
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
        return task
    }

    func delete(id: Int) async throws {
        if let deleteError {
            throw deleteError
        }
        deletedIDs.append(id)
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
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
    var addError: VikunjaError?
    var removeError: VikunjaError?
    private(set) var addedLabelIDs: [(labelID: Int, taskID: Int)] = []
    private(set) var removedLabelIDs: [(labelID: Int, taskID: Int)] = []

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

    var addError: VikunjaError?
    private(set) var addedRelations: [RecordedRelation] = []

    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        if let addError {
            throw addError
        }
        addedRelations.append(RecordedRelation(kind: kind, otherTaskID: otherTaskID, taskID: taskID))
    }

    func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {}
}

@MainActor
final class FakeToastPresenter: ToastPresenting {
    private(set) var shown: [(message: String, style: ToastStyle)] = []

    func show(_ message: String, style: ToastStyle) {
        shown.append((message, style))
    }
}

@MainActor
final class FakeHapticPresenter: HapticFeedbackPresenting {
    private(set) var played: [HapticStyle] = []

    func play(_ style: HapticStyle) {
        played.append(style)
    }
}
