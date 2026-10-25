import Foundation
import GRDB

/// Row shape of the `syncState` table: when an entity type was last pulled
/// in full. One row per entity, keyed by the same free-text discriminator
/// `MutationEntityType` uses.
struct SyncStateRecord: Codable, Equatable, Sendable {
    var entityType: MutationEntityType
    var lastPulledAt: Date
}

extension SyncStateRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncState"
}
