import VikunjaCore

/// Routes each `LabelRepositoryProtocol` call to the v1 or v2 concrete
/// repository based on `CapabilityProvider.supports(.apiV2)` — see
/// `VikunjaProjectRepositorySwitch` for the full rationale (identical
/// pattern, one per resource per `docs/API_V2_MIGRATION.md`'s Step 3).
final class VikunjaLabelRepositorySwitch: LabelRepositoryProtocol {
    private let v1: LabelRepositoryProtocol
    private let v2: LabelRepositoryProtocol
    private let capabilityProvider: CapabilityProvider

    init(v1: LabelRepositoryProtocol, v2: LabelRepositoryProtocol, capabilityProvider: CapabilityProvider) {
        self.v1 = v1
        self.v2 = v2
        self.capabilityProvider = capabilityProvider
    }

    private func resolve() async -> LabelRepositoryProtocol {
        await capabilityProvider.supports(.apiV2) ? v2 : v1
    }

    func fetchLabels() async throws -> [Label] {
        try await resolve().fetchLabels()
    }

    func create(_ label: Label) async throws -> Label {
        try await resolve().create(label)
    }

    func update(_ label: Label) async throws -> Label {
        try await resolve().update(label)
    }

    func delete(id: Int) async throws {
        try await resolve().delete(id: id)
    }

    func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        try await resolve().addLabel(labelID, toTask: taskID)
    }

    func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        try await resolve().removeLabel(labelID, fromTask: taskID)
    }
}
