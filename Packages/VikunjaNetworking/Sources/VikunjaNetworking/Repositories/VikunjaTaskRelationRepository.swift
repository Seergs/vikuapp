import VikunjaCore

public final class VikunjaTaskRelationRepository: TaskRelationRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws {
        guard let resolvedOtherTaskID = otherTaskID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskRelationRepository.addRelation: both tasks must be synced first")
        }
        try await client.send(
            VikunjaEndpoints.createTaskRelation(taskID: resolvedTaskID, kind: kind, otherTaskID: resolvedOtherTaskID),
        )
    }

    public func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws {
        guard let resolvedOtherTaskID = otherTaskID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskRelationRepository.removeRelation: both tasks must be synced first")
        }
        try await client.send(
            VikunjaEndpoints.deleteTaskRelation(taskID: resolvedTaskID, kind: kind, otherTaskID: resolvedOtherTaskID),
        )
    }
}
