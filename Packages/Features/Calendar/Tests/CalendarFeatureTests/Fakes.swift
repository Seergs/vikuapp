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
    var beforeUpdate: (@Sendable () async -> Void)?

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
        guard let task = tasks.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
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
        tasks.removeAll { $0.id == id }
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
