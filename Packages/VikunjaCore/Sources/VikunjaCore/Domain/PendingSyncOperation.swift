import Foundation

/// Which kind of local entity a queued mutation targets.
public enum PendingSyncEntity: String, Hashable, Sendable {
    case project
    case filter
    case label
    case task
    case comment
}

/// What a queued mutation does to its target.
public enum PendingSyncAction: String, Hashable, Sendable {
    case moveBucket
    case create
    case update
    case delete
    case addLabel
    case removeLabel
    case addRelation
    case removeRelation
}

/// One entry in an account's offline mutation queue, as shown by the
/// "Pending Sync" screen. Carries the resolved target title so the screen
/// doesn't need a repository per entity type; `targetTitle` is `nil` when
/// the local row is already gone (for example a delete whose row was pruned
/// before the queued mutation drained).
public struct PendingSyncOperation: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let entity: PendingSyncEntity
    public let action: PendingSyncAction
    public let targetTitle: String?
    public let createdAt: Date
    public let status: SyncItemStatus
    /// A conflict is reported as `.failed` too, but the screen shows a
    /// distinct "Conflict" label because it needs a person to resolve it
    /// rather than just waiting for a retry.
    public let needsConflictResolution: Bool
    public let failureMessage: String?
    public let canRecoverKanbanCreation: Bool

    public init(
        id: Int64,
        entity: PendingSyncEntity,
        action: PendingSyncAction,
        targetTitle: String?,
        createdAt: Date,
        status: SyncItemStatus,
        needsConflictResolution: Bool,
        failureMessage: String? = nil,
        canRecoverKanbanCreation: Bool = false,
    ) {
        self.id = id
        self.entity = entity
        self.action = action
        self.targetTitle = targetTitle
        self.createdAt = createdAt
        self.status = status
        self.needsConflictResolution = needsConflictResolution
        self.failureMessage = failureMessage
        self.canRecoverKanbanCreation = canRecoverKanbanCreation
    }
}
