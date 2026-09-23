import VikunjaCore

/// Routes each `ProjectRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)`, resolved fresh
/// per call — `VikunjaCapabilityProvider`'s in-memory cache keeps that cheap
/// after the first hit for as long as this switch instance lives. A small
/// explicit wrapper rather than a generic one, per
/// `docs/API_V2_MIGRATION.md`'s Step 3 recipe: `InstanceClientFactoryProtocol`
/// stays synchronous, so nothing outside `Repositories/` needs to change to
/// check an async capability.
final class VikunjaProjectRepositorySwitch: ProjectRepositoryProtocol {
    private let v1: ProjectRepositoryProtocol
    private let v2: ProjectRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: ProjectRepositoryProtocol, v2: ProjectRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> ProjectRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchProjects() async throws -> [Project] {
        try await resolve().fetchProjects()
    }

    func fetchProject(id: Int) async throws -> Project {
        try await resolve().fetchProject(id: id)
    }

    func create(_ project: Project) async throws -> Project {
        try await resolve().create(project)
    }

    func update(_ project: Project) async throws -> Project {
        try await resolve().update(project)
    }

    func delete(id: Int) async throws {
        try await resolve().delete(id: id)
    }
}
