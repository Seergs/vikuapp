import Foundation

/// Saves a plain task to the account's configured default project.
public struct DefaultProjectTaskCreator: Sendable {
    public enum Failure: Error {
        case emptyTitle
        case missingDefaultProject
        case unavailableDefaultProject
    }

    private let projectRepository: ProjectRepositoryProtocol
    private let taskRepository: TaskRepositoryProtocol

    public init(projectRepository: ProjectRepositoryProtocol, taskRepository: TaskRepositoryProtocol) {
        self.projectRepository = projectRepository
        self.taskRepository = taskRepository
    }

    public func create(
        title: String, defaultProjectID: Int?,
    ) async throws -> (task: VikunjaTask, project: Project) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Failure.emptyTitle }
        guard let defaultProjectID else { throw Failure.missingDefaultProject }
        guard defaultProjectID > 0 else { throw Failure.unavailableDefaultProject }

        let project: Project
        do {
            project = try await projectRepository.fetchProject(id: .remote(defaultProjectID))
        } catch VikunjaError.notFound {
            throw Failure.unavailableDefaultProject
        }
        guard !project.isArchived else { throw Failure.unavailableDefaultProject }

        try Task.checkCancellation()
        let task = try await taskRepository.create(VikunjaTask(id: 0, title: title, projectID: project.id))
        return (task, project)
    }
}
