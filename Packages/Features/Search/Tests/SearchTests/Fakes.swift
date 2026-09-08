@testable import Search
import VikunjaCore

final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    private(set) var updatedTasks: [VikunjaTask] = []
    private(set) var deletedIDs: [Int] = []

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        tasks.filter { $0.projectID == projectID }
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

    func fetchProjects() async throws -> [Project] {
        projects
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
