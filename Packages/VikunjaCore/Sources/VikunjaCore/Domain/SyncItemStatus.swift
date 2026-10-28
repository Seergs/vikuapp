import Foundation

/// Which kind of local entity a pending-sync entry refers to. `EntityID`
/// alone can't identify one, since every entity type uses the same
/// `local(UUID)`/`remote(Int)` shape and a task and a project may share the
/// same server id, so a lookup key combines both.
public enum SyncItemKind: String, Hashable, Sendable {
    case project
    case task
}

/// Identifies one project or task for a pending-sync status lookup.
public struct SyncItemKey: Hashable, Sendable {
    public let kind: SyncItemKind
    public let id: EntityID

    public init(kind: SyncItemKind, id: EntityID) {
        self.kind = kind
        self.id = id
    }
}

/// The sync state of an entity that has at least one queued local mutation.
/// Aggregated per entity: a later mutation that failed (or needs a conflict
/// resolved) wins over a newer one that's merely waiting its turn.
public enum SyncItemStatus: String, Hashable, Sendable {
    /// Queued and waiting to be pushed, either because the device is offline
    /// or because the queue hasn't reached it yet.
    case pending
    /// A push attempt failed, or the queued edit conflicts with a newer
    /// server-side change and needs a person to resolve it.
    case failed
}
