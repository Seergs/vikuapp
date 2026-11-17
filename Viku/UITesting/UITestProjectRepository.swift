#if DEBUG
import Foundation
import VikunjaCore

actor UITestProjectRepository: ProjectRepositoryProtocol {
    private var projects = [
        Project(id: 1, title: "UI Test Project"),
        Project(id: 2, title: "UI Test Context Project"),
    ]
    private var nextID = 100

    func fetchProjects() async throws -> [Project] {
        projects
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        let created = Project(
            id: .remote(nextID), title: project.title, description: project.description,
            isArchived: project.isArchived, isFavorite: project.isFavorite, parentProjectID: project.parentProjectID,
            position: project.position, hexColor: project.hexColor, updated: Date(),
        )
        nextID += 1
        projects.append(created)
        return created
    }

    func update(_ project: Project) async throws -> Project {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { throw VikunjaError.notFound }
        var updated = project
        updated.updated = Date()
        projects[index] = updated
        return updated
    }

    func delete(id: EntityID) async throws {
        projects.removeAll { $0.id == id }
    }
}
#endif
