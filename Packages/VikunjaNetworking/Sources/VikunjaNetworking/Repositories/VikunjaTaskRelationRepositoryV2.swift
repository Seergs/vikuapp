import VikunjaCore

/// v2 implementation of `TaskRelationRepositoryProtocol`. Reuses v1's
/// `CreateTaskRelationDTO` — verified against a real instance's
/// `/api/v2/openapi.json`: v2's `TaskRelation` schema's `relation_kind` /
/// `other_task_id` match the DTO's fields exactly, and its `RelationKind`
/// enum values match `VikunjaCore.RelationKind`'s cases one for one. Neither
/// method returns a domain value, so there's no response body to decode —
/// just a status check, same as v1.
public final class VikunjaTaskRelationRepositoryV2: TaskRelationRepositoryProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws {
        guard let resolvedOtherTaskID = otherTaskID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskRelationRepositoryV2.addRelation: both tasks must be synced first")
        }
        let endpoint = try VikunjaEndpoints.createTaskRelationV2(
            taskID: resolvedTaskID, kind: kind, otherTaskID: resolvedOtherTaskID,
        )
        try await client.send(endpoint)
    }

    public func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws {
        guard let resolvedOtherTaskID = otherTaskID.remoteValue, let resolvedTaskID = taskID.remoteValue else {
            preconditionFailure("VikunjaTaskRelationRepositoryV2.removeRelation: both tasks must be synced first")
        }
        let endpoint = VikunjaEndpoints.deleteTaskRelationV2(
            taskID: resolvedTaskID, kind: kind, otherTaskID: resolvedOtherTaskID,
        )
        try await client.send(endpoint)
    }
}
