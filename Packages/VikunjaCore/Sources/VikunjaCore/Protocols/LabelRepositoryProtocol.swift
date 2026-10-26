public protocol LabelRepositoryProtocol: Sendable {
    func fetchLabels() async throws -> [Label]
    func create(_ label: Label) async throws -> Label
    func update(_ label: Label) async throws -> Label
    func delete(id: EntityID) async throws

    func addLabel(_ labelID: Int, toTask taskID: Int) async throws
    func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws
}
