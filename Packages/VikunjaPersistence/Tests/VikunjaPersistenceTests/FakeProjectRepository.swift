import Foundation
import VikunjaCore

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var fetchError: Error?
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    private(set) var createdProjects: [Project] = []
    private(set) var updatedProjects: [Project] = []
    private(set) var deletedIDs: [Int] = []
    private(set) var fetchProjectsCallCount = 0
    private var nextRemoteID = 100
    /// Lets a test hold `fetchProjects()` open for a bit — simulating a
    /// slow network call still in flight — so it can start a second,
    /// overlapping sync against the same account and check it was skipped
    /// rather than racing a second `fetchProjects()` call of its own.
    var fetchDelay: Duration?
    var beforeFetchResponse: (@Sendable () async -> Void)?
    var onFetchProjects: (@Sendable () -> Void)?
    var beforeCreateResponse: (@Sendable () async throws -> Void)?
    var beforeUpdateResponse: (@Sendable () async throws -> Void)?

    func fetchProjects() async throws -> [Project] {
        fetchProjectsCallCount += 1
        onFetchProjects?()
        if let fetchDelay {
            try await Task.sleep(for: fetchDelay)
        }
        await beforeFetchResponse?()
        if let fetchError {
            throw fetchError
        }
        return projects
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return project
    }

    /// Simulates the server assigning a real id and `updated` timestamp —
    /// `SyncEngine.applyPushResult` requires both to be present. Also adds
    /// it to `projects`, like a real server would list it back on the very
    /// next `fetchProjects()` call.
    func create(_ project: Project) async throws -> Project {
        if let createError {
            throw createError
        }
        createdProjects.append(project)
        let remoteID = nextRemoteID
        nextRemoteID += 1
        let created = Self.withServerAssigned(project, id: .remote(remoteID))
        projects.append(created)
        try await beforeCreateResponse?()
        return created
    }

    func update(_ project: Project) async throws -> Project {
        try await beforeUpdateResponse?()
        if let updateError {
            throw updateError
        }
        updatedProjects.append(project)
        let updated = Self.withServerAssigned(project, id: project.id)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        }
        return updated
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
