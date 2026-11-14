import Foundation
import GRDB
import VikunjaCore

struct QuickAddSettingsRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "quickAddSettings"
    var accountID: UUID
    var mode: QuickAddMagicMode
    var revision: UUID

    static func pending(accountID: UUID, db: Database) throws -> MutationQueueRecord? {
        try MutationQueueRecord.filter(Column("accountID") == accountID)
            .filter(Column("entityType") == MutationEntityType.quickAddSettings.rawValue).fetchOne(db)
    }

    static func settings(accountID: UUID, db: Database) throws -> QuickAddMagicSettings {
        let row = try fetchOne(db, key: accountID)
        let pending = try pending(accountID: accountID, db: db)
        return QuickAddMagicSettings(
            mode: row?.mode,
            syncStatus: pending.map { $0.status == .failed ? .failed : .pending },
            failureMessage: pending.flatMap { StoredSyncFailure.decode($0.failureDetails)?.displayMessage },
        )
    }
}
