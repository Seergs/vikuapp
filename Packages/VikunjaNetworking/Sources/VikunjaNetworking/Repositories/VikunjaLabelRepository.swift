import VikunjaCore

public final class VikunjaLabelRepository: LabelRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchLabels() async throws -> [Label] {
        let dtos: [LabelDTO] = try await client.send(VikunjaEndpoints.labels())
        return dtos.map(LabelMapper.toDomain)
    }

    public func create(_ label: Label) async throws -> Label {
        let endpoint = try VikunjaEndpoints.createLabel(dto: LabelMapper.toDTO(label))
        let dto: LabelDTO = try await client.send(endpoint)
        return LabelMapper.toDomain(dto)
    }

    public func update(_ label: Label) async throws -> Label {
        guard let id = label.id.remoteValue else {
            preconditionFailure("VikunjaLabelRepository.update: label must be synced before it can be updated")
        }
        let endpoint = try VikunjaEndpoints.updateLabel(id: id, dto: LabelMapper.toDTO(label))
        let dto: LabelDTO = try await client.send(endpoint)
        return LabelMapper.toDomain(dto)
    }

    public func delete(id: Int) async throws {
        try await client.send(VikunjaEndpoints.deleteLabel(id: id))
    }

    public func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        try await client.send(VikunjaEndpoints.addLabelToTask(taskID: taskID, labelID: labelID))
    }

    public func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        try await client.send(VikunjaEndpoints.removeLabelFromTask(taskID: taskID, labelID: labelID))
    }
}
