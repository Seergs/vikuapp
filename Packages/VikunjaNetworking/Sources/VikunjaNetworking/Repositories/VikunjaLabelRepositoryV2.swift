import VikunjaCore

/// v2 implementation of `LabelRepositoryProtocol`. Reuses v1's `LabelDTO` /
/// `TaskLabelDTO` / `LabelMapper` rather than adding a `LabelDTOV2` —
/// verified against a real instance's `/api/v2/openapi.json`: v2's `Label`
/// schema adds `created`, `created_by`, `description`, `updated` (this app
/// doesn't model those) but `id`, `title`, `hex_color` have the same name
/// and type in both versions, and `LabelTask`'s `label_id` matches
/// `TaskLabelDTO` exactly.
public final class VikunjaLabelRepositoryV2: LabelRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchLabels() async throws -> [Label] {
        let envelope: APIv2Envelope<LabelDTO> = try await client.send(VikunjaEndpoints.labelsV2())
        return envelope.items.map(LabelMapper.toDomain)
    }

    public func create(_ label: Label) async throws -> Label {
        let endpoint = try VikunjaEndpoints.createLabelV2(dto: LabelMapper.toDTO(label))
        let dto: LabelDTO = try await client.send(endpoint)
        return LabelMapper.toDomain(dto)
    }

    public func update(_ label: Label) async throws -> Label {
        let endpoint = try VikunjaEndpoints.updateLabelV2(id: label.id, dto: LabelMapper.toDTO(label))
        let dto: LabelDTO = try await client.send(endpoint)
        return LabelMapper.toDomain(dto)
    }

    public func delete(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteLabelV2(id: id))
    }

    public func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        let endpoint = try VikunjaEndpoints.addLabelToTaskV2(taskID: taskID, labelID: labelID)
        try await client.send(endpoint)
    }

    public func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        try await client.send(VikunjaEndpoints.removeLabelFromTaskV2(taskID: taskID, labelID: labelID))
    }
}
