public protocol LabelRepositoryProtocol: Sendable {
    func fetchLabels() async throws -> [Label]
    /// Reads labels and identity aliases together. Local repositories retain the
    /// local ID as an alias after sync; server-only implementations need no aliases.
    func fetchLabelCatalog() async throws -> LabelCatalog
    func create(_ label: Label) async throws -> Label
    func update(_ label: Label) async throws -> Label
    func delete(id: EntityID) async throws

    func addLabel(_ labelID: EntityID, toTask taskID: EntityID) async throws
    func removeLabel(_ labelID: EntityID, fromTask taskID: EntityID) async throws
}

public extension LabelRepositoryProtocol {
    func fetchLabelCatalog() async throws -> LabelCatalog {
        try await LabelCatalog(labels: fetchLabels())
    }
}
