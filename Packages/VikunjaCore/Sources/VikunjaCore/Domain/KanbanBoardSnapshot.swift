import Foundation

/// A missing snapshot is different from a downloaded board with no cards.
public enum KanbanBoardSnapshot: Equatable, Sendable {
    case waitingForProject
    case unavailable
    case available(KanbanBoard)
}

public struct KanbanBoard: Equatable, Sendable {
    public let viewID: Int
    public let buckets: [KanbanBucket]
    public let defaultBucketID: Int?
    public let supportsWrites: Bool
    public let supportsTaskCreation: Bool
    public let requiresConnection: Bool
    public let lastPulledAt: Date

    public init(
        viewID: Int, buckets: [KanbanBucket], defaultBucketID: Int?,
        supportsWrites: Bool, lastPulledAt: Date,
        supportsTaskCreation: Bool = true, requiresConnection: Bool = false,
    ) {
        self.viewID = viewID
        self.buckets = buckets
        self.defaultBucketID = defaultBucketID
        self.supportsWrites = supportsWrites
        self.supportsTaskCreation = supportsTaskCreation
        self.requiresConnection = requiresConnection
        self.lastPulledAt = lastPulledAt
    }
}
