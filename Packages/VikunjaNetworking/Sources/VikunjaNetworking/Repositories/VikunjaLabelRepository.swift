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

    public func delete(id: EntityID) async throws {
        guard let id = id.remoteValue else {
            preconditionFailure("VikunjaLabelRepository.delete: label must be synced before it can be deleted")
        }
        try await client.send(VikunjaEndpoints.deleteLabel(id: id))
    }

    public func addLabel(_ labelID: EntityID, toTask taskID: EntityID) async throws {
        guard let labelID = labelID.remoteValue, let taskID = taskID.remoteValue else {
            preconditionFailure("VikunjaLabelRepository.addLabel: both the label and task must be synced first")
        }
        try await client.send(VikunjaEndpoints.addLabelToTask(taskID: taskID, labelID: labelID))
    }

    public func removeLabel(_ labelID: EntityID, fromTask taskID: EntityID) async throws {
        guard let labelID = labelID.remoteValue, let taskID = taskID.remoteValue else {
            preconditionFailure("VikunjaLabelRepository.removeLabel: both the label and task must be synced first")
        }
        try await client.send(VikunjaEndpoints.removeLabelFromTask(taskID: taskID, labelID: labelID))
    }
}
