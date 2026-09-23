import VikunjaCore

/// v2 implementation of `ProjectRepositoryProtocol`. Reuses v1's `ProjectDTO`
/// / `ProjectMapper` rather than adding a `ProjectDTOV2` — verified against a
/// real instance's `/api/v2/openapi.json`: v2's `Project` schema adds fields
/// (`identifier`, `max_permission`, `owner`, `subscription`, `views`,
/// `created`, `updated`, background info) this app doesn't model, but every
/// field `ProjectDTO` already decodes (`id`, `title`, `description`,
/// `is_archived`, `is_favorite`, `parent_project_id`, `position`,
/// `hex_color`) has the same name and type in both versions — the extra v2
/// fields just get ignored by `Decodable`.
final class VikunjaProjectRepositoryV2: ProjectRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchProjects() async throws -> [Project] {
        let envelope: APIv2Envelope<ProjectDTO> = try await client.send(VikunjaEndpoints.projectsV2())
        return envelope.items.map(ProjectMapper.toDomain)
    }

    func fetchProject(id: Int) async throws -> Project {
        let dto: ProjectDTO = try await client.send(VikunjaEndpoints.projectV2(id: id))
        return ProjectMapper.toDomain(dto)
    }

    func create(_ project: Project) async throws -> Project {
        let endpoint = try VikunjaEndpoints.createProjectV2(dto: ProjectMapper.toDTO(project))
        let dto: ProjectDTO = try await client.send(endpoint)
        return ProjectMapper.toDomain(dto)
    }

    func update(_ project: Project) async throws -> Project {
        let endpoint = try VikunjaEndpoints.updateProjectV2(id: project.id, dto: ProjectMapper.toDTO(project))
        let dto: ProjectDTO = try await client.send(endpoint)
        return ProjectMapper.toDomain(dto)
    }

    func delete(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteProjectV2(id: id))
    }
}
