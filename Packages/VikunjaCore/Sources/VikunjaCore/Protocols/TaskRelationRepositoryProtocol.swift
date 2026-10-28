public protocol TaskRelationRepositoryProtocol: Sendable {
    func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws
    func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws
}
