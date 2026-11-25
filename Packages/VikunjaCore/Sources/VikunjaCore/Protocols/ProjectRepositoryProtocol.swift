public protocol ProjectRepositoryProtocol: Sendable {
    func fetchProjects() async throws -> [Project]
    func fetchProject(id: EntityID) async throws -> Project
    func create(_ project: Project) async throws -> Project
    func update(_ project: Project) async throws -> Project
    func editProject(id: EntityID, title: String, hexColor: String, parentProjectID: EntityID?) async throws -> Project
    func delete(id: EntityID) async throws
}

public extension ProjectRepositoryProtocol {
    func editProject(id: EntityID, title: String, hexColor: String, parentProjectID: EntityID?) async throws -> Project {
        var project = try await fetchProject(id: id)
        project.title = title
        project.hexColor = hexColor
        project.parentProjectID = parentProjectID
        return try await update(project)
    }
}
