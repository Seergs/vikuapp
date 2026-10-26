import Foundation
import VikunjaCore

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    private(set) var createdProjects: [Project] = []
    private(set) var updatedProjects: [Project] = []
    private(set) var deletedIDs: [Int] = []
    private var nextRemoteID = 100

    func fetchProjects() async throws -> [Project] {
        projects
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return project
    }

    /// Simulates the server assigning a real id and `updated` timestamp —
    /// `SyncEngine.applyPushResult` requires both to be present.
    func create(_ project: Project) async throws -> Project {
        if let createError {
            throw createError
        }
        createdProjects.append(project)
        let remoteID = nextRemoteID
        nextRemoteID += 1
        return Self.withServerAssigned(project, id: .remote(remoteID))
    }

    func update(_ project: Project) async throws -> Project {
        if let updateError {
            throw updateError
        }
        updatedProjects.append(project)
        return Self.withServerAssigned(project, id: project.id)
    }

    func delete(id: EntityID) async throws {
        if let deleteError {
            throw deleteError
        }
        if let remoteID = id.remoteValue {
            deletedIDs.append(remoteID)
        }
        projects.removeAll { $0.id == id }
    }

    private static func withServerAssigned(_ project: Project, id: EntityID) -> Project {
        Project(
            id: id,
            title: project.title,
            description: project.description,
            isArchived: project.isArchived,
            isFavorite: project.isFavorite,
            parentProjectID: project.parentProjectID,
            position: project.position,
            hexColor: project.hexColor,
            updated: Date(),
        )
    }
}
