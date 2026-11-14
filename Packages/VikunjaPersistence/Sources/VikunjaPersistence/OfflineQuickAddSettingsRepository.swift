import Foundation
import GRDB
import VikunjaCore

public actor OfflineQuickAddSettingsRepository: QuickAddSettingsRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncRequester: SyncRequesting

    public init(localStore: LocalStore, accountID: UUID, syncRequester: SyncRequesting) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
    }

    public func settings() async throws -> QuickAddMagicSettings {
        try await localStore.read { db in
            try QuickAddSettingsRecord.settings(accountID: self.accountID, db: db)
        }
    }

    public func setMode(_ mode: QuickAddMagicMode) async throws {
        try await localStore.write { db in
            try QuickAddSettingsRecord(accountID: self.accountID, mode: mode, revision: UUID()).save(db)
            // Always allocate a new queue identity. An old in-flight response can
            // never acknowledge or fail a newer choice, even after choosing A→B→A.
            try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("entityType") == MutationEntityType.quickAddSettings.rawValue).deleteAll(db)
            var item = MutationQueueRecord(
                id: nil, accountID: self.accountID, entityType: .quickAddSettings, operation: .update,
                targetLocalID: self.accountID, payload: mode.rawValue, createdAt: Date(), retryCount: 0,
                lastError: nil, status: .pending, needsConflictResolution: false,
            )
            try item.insert(db)
        }
        await syncRequester.requestSync()
    }

    public func retrySync() async {
        await syncRequester.requestSync()
    }

    public func observeSettings() async -> AsyncThrowingStream<QuickAddMagicSettings, Error> {
        await localStore.observeQuickAddSettings(accountID: accountID)
    }
}
