import VikunjaCore

/// Routes each `TaskRelationRepositoryProtocol` call to the v1 or v2
/// concrete repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource).
final class VikunjaTaskRelationRepositorySwitch: TaskRelationRepositoryProtocol {
    private let v1: TaskRelationRepositoryProtocol
    private let v2: TaskRelationRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: TaskRelationRepositoryProtocol, v2: TaskRelationRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> TaskRelationRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        try await resolve().addRelation(kind: kind, otherTaskID: otherTaskID, toTask: taskID)
    }

    func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {
        try await resolve().removeRelation(kind: kind, otherTaskID: otherTaskID, fromTask: taskID)
    }
}
