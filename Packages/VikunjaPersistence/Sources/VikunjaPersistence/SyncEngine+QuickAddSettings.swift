import Foundation
import GRDB
import VikunjaCore

extension SyncEngine {
    /// A pending local choice wins this upload. With no pending choice the
    /// remote value wins. No conflict prompt or legacy-device migration.
    func syncQuickAddSettings() async throws {
        guard let userRepository else { return }
        let baseline = try await localStore.read { db in
            try (
                QuickAddSettingsRecord.fetchOne(db, key: self.accountID),
                QuickAddSettingsRecord.pending(accountID: self.accountID, db: db),
            )
        }
        let (original, pending) = baseline
        do {
            let user: User
            if let pending {
                guard let raw = pending.payload, let mode = QuickAddMagicMode(rawValue: raw) else {
                    throw VikunjaError.decoding("Invalid queued Quick Add Magic mode")
                }
                user = try await userRepository.updateQuickAddMagicMode(mode)
            } else {
                user = try await userRepository.fetchCurrentUser()
            }
            guard let mode = user.quickAddMagicMode else {
                throw VikunjaError.decoding("Unsupported Quick Add Magic settings")
            }
            try Task.checkCancellation()
            try await localStore.write { db in
                try Self.commitQuickAddSettings(
                    mode, original: original, pending: pending, accountID: self.accountID, db: db,
                )
            }
        } catch {
            try checkSyncInterruption(error)
            if let pending {
                try await localStore.write { db in
                    guard var current = try MutationQueueRecord.fetchOne(db, key: pending.id) else { return }
                    current.status = .failed
                    current.retryCount += 1
                    current.recordFailure(error)
                    try current.update(db)
                }
            }
            throw error
        }
    }

    /// Acknowledgement and cache replacement share one transaction with the
    /// revision checks, so a concurrently enqueued choice remains untouched.
    private static func commitQuickAddSettings(
        _ mode: QuickAddMagicMode,
        original: QuickAddSettingsRecord?,
        pending: MutationQueueRecord?,
        accountID: UUID,
        db: Database,
    ) throws {
        let current = try QuickAddSettingsRecord.fetchOne(db, key: accountID)
        guard current?.revision == original?.revision else { return }
        let queued = try QuickAddSettingsRecord.pending(accountID: accountID, db: db)
        guard queued?.id == pending?.id else { return }
        if let queued {
            try queued.delete(db)
        }
        // A successful refresh of an unchanged value must not invalidate every
        // account-content observer through a gratuitous revision change.
        if current?.mode != mode {
            try QuickAddSettingsRecord(accountID: accountID, mode: mode, revision: UUID()).save(db)
        }
    }
}
