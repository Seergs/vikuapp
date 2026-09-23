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

    public func addRelation(kind: RelationKind, otherTaskID: Int, toTask taskID: Int) async throws {
        let endpoint = try VikunjaEndpoints.createTaskRelationV2(taskID: taskID, kind: kind, otherTaskID: otherTaskID)
        try await client.send(endpoint)
    }

    public func removeRelation(kind: RelationKind, otherTaskID: Int, fromTask taskID: Int) async throws {
        let endpoint = VikunjaEndpoints.deleteTaskRelationV2(taskID: taskID, kind: kind, otherTaskID: otherTaskID)
        try await client.send(endpoint)
    }
}
