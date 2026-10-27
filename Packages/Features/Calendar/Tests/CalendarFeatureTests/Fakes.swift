@testable import CalendarFeature
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
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
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

final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var fetchError: VikunjaError?
    var failingProjectIDs: Set<Int> = []
    var updateError: VikunjaError?

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        if let fetchError {
            throw fetchError
        }
        if failingProjectIDs.contains(projectID) {
            throw VikunjaError.network("offline")
        }
        return tasks.filter { $0.projectID.remoteValue == projectID }
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id.remoteValue == id }) else { throw VikunjaError.notFound }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let updateError {
            throw updateError
        }
        return task
    }

    func delete(id: Int) async throws {
        tasks.removeAll { $0.id.remoteValue == id }
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

final class FakeHapticPresenter: HapticFeedbackPresenting, @unchecked Sendable {
    private(set) var played: [HapticStyle] = []
    func play(_ style: HapticStyle) {
        played.append(style)
    }
}
