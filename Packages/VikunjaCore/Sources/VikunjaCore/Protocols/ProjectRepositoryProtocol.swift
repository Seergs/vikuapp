public protocol ProjectRepositoryProtocol: Sendable {
    func fetchProjects() async throws -> [Project]
    func fetchProject(id: EntityID) async throws -> Project
    func create(_ project: Project) async throws -> Project
    func update(_ project: Project) async throws -> Project
    func delete(id: EntityID) async throws
}
