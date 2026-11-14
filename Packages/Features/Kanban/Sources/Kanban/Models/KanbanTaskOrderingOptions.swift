import VikunjaCore

/// Captured with the menu so a later bucket/view change cannot redirect its action.
public struct KanbanTaskOrderingOptions: Equatable, Sendable {
    public let taskID: EntityID
    public let viewID: Int
    public let bucketID: Int
    public let placements: [KanbanTaskPlacement]
}
