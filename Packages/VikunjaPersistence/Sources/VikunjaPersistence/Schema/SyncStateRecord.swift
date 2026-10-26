import Foundation
import GRDB

/// Row shape of the `syncState` table: when an account last pulled an
/// entity type in full. One row per account per entity, keyed by the same
/// free-text discriminator `MutationEntityType` uses.
struct SyncStateRecord: Codable, Equatable, Sendable {
    var accountID: UUID
    var entityType: MutationEntityType
    var lastPulledAt: Date
}

extension SyncStateRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncState"
}
