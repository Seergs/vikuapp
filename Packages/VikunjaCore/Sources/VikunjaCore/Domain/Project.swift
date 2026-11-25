import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public let id: EntityID
    public var title: String
    public var description: String?
    public var isArchived: Bool
    public var isFavorite: Bool
    public var parentProjectID: EntityID?
    public var position: Double
    public var hexColor: String
    /// The server's own last-modified timestamp. `nil` for a project that
    /// hasn't round-tripped through the network yet (a freshly offline-
    /// created one). Not for display — it's sync bookkeeping, read by
    /// whatever persists this project locally.
    public var updated: Date?
    /// The cache identity survives the transition from a local to a server ID.
    public let localID: UUID?
    /// Set while an online creation is waiting for its server position.
    public let pendingOnlineCreationAt: Date?

    public init(
        id: EntityID,
        title: String,
        description: String? = nil,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        parentProjectID: EntityID? = nil,
        position: Double = 0,
        hexColor: String = "",
        updated: Date? = nil,
        localID: UUID? = nil,
        pendingOnlineCreationAt: Date? = nil,
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.parentProjectID = parentProjectID
        self.position = position
        self.hexColor = hexColor
        self.updated = updated
        self.localID = localID
        self.pendingOnlineCreationAt = pendingOnlineCreationAt
    }

    public var displayID: EntityID {
        localID.map(EntityID.local) ?? id
    }

    public var kind: ProjectKind {
        // A `.local` id (offline-created, not yet synced) is always a real
        // project — Favorites/saved filters are server-defined constants,
        // never created on-device.
        guard let rawID = id.remoteValue else {
            return .project
        }
        if rawID == -1 {
            return .favorites
        }
        if rawID < 0 {
            return .savedFilter
        }
        return .project
    }
}
