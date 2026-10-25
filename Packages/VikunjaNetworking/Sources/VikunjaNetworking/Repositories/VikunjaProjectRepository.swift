import VikunjaCore

public final class VikunjaProjectRepository: ProjectRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchProjects() async throws -> [Project] {
        let dtos: [ProjectDTO] = try await client.send(VikunjaEndpoints.projects())
        return dtos.map(ProjectMapper.toDomain)
    }

    public func fetchProject(id: Int) async throws -> Project {
        let dto: ProjectDTO = try await client.send(VikunjaEndpoints.project(id: id))
        return ProjectMapper.toDomain(dto)
    }

    public func create(_ project: Project) async throws -> Project {
        let endpoint = try VikunjaEndpoints.createProject(dto: ProjectMapper.toDTO(project))
        let dto: ProjectDTO = try await client.send(endpoint)
        return ProjectMapper.toDomain(dto)
    }

    public func update(_ project: Project) async throws -> Project {
        guard let id = project.id.remoteValue else {
            preconditionFailure("VikunjaProjectRepository.update: project must be synced before it can be updated")
        }
        let endpoint = try VikunjaEndpoints.updateProject(id: id, dto: ProjectMapper.toDTO(project))
        let dto: ProjectDTO = try await client.send(endpoint)
        return ProjectMapper.toDomain(dto)
    }

    public func delete(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteProject(id: id))
    }
}
