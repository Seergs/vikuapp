#if DEBUG
import Foundation
import VikunjaCore

actor UITestProjectRepository: ProjectRepositoryProtocol {
    private var projects = [
        Project(id: 1, title: "UI Test Project"),
        Project(id: 2, title: "UI Test Context Project"),
        UITestFixtures.savedFilterProject,
    ]
    private var nextID = 100
    private let delaysProjectCreation: Bool

    init() {
        let delaysProjectCreation = ProcessInfo.processInfo.arguments.contains("-UITestSlowProjectCreation")
        self.delaysProjectCreation = delaysProjectCreation
        if ProcessInfo.processInfo.arguments.contains("-UITestLongProjectList") {
            projects += (3 ... 32).map {
                Project(id: .remote($0), title: "UI Test Project \($0)", position: delaysProjectCreation ? Double($0) : 0)
            }
        }
    }

    func fetchProjects() async throws -> [Project] {
        projects
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        if delaysProjectCreation {
            try await Task.sleep(for: .seconds(6))
        }
        let created = Project(
            id: .remote(nextID), title: project.title, description: project.description,
            isArchived: project.isArchived, isFavorite: project.isFavorite, parentProjectID: project.parentProjectID,
            position: delaysProjectCreation ? 18.5 : project.position, hexColor: project.hexColor, updated: Date(),
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
