import VikunjaCore

/// Routes each `TaskRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource).
final class VikunjaTaskRepositorySwitch: TaskRepositoryProtocol {
    private let v1: TaskRepositoryProtocol
    private let v2: TaskRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: TaskRepositoryProtocol, v2: TaskRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> TaskRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        try await resolve().fetchTasks(projectID: projectID)
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        try await resolve().fetchTask(id: id)
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        try await resolve().create(task)
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        try await resolve().update(task)
    }

    func delete(id: Int) async throws {
        try await resolve().delete(id: id)
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        try await resolve().searchTasks(query: query)
    }
}
