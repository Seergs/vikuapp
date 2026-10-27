import Foundation
import GRDB
import VikunjaCore

/// Local-first `LabelRepositoryProtocol` — same shape as
/// `OfflineProjectRepository`, minus the hierarchy and conflict-detection
/// machinery projects need: a label is just a title and a color, with
/// nothing else depending on it syncing in any particular order.
///
/// `addLabel`/`removeLabel` (attaching a label to a task) are a plain
/// pass-through to `networkLabelRepository`, never queued here — that's
/// task-label association, which stays online-only until task offline
/// support (Slice 4) exists to give it somewhere to queue against.
public actor OfflineLabelRepository: LabelRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncEngine: SyncEngine
    private let reachability: ReachabilityMonitoring
    private let networkLabelRepository: LabelRepositoryProtocol

    public init(
        localStore: LocalStore,
        accountID: UUID,
        syncEngine: SyncEngine,
        reachability: ReachabilityMonitoring,
        networkLabelRepository: LabelRepositoryProtocol,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncEngine = syncEngine
        self.reachability = reachability
        self.networkLabelRepository = networkLabelRepository
    }

    public func fetchLabels() async throws -> [Label] {
        await pullIfNeverSynced()
        return try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) }
                .map(Self.label(from:))
        }
    }

    public func create(_ label: Label) async throws -> Label {
        let localID = UUID()
        try await localStore.write { db in
            try LabelRecord(
                localID: localID,
                accountID: self.accountID,
                remoteID: nil,
                title: label.title,
                hexColor: label.hexColor,
            ).insert(db)
            let payload = LabelCreateOrUpdatePayload(title: label.title, hexColor: label.hexColor)
            try Self.enqueueOrCoalesce(
                operation: .create, targetLocalID: localID, accountID: self.accountID, payload: payload, db: db,
            )
        }
        await triggerDrainIfOnline()
        return try await readLabel(id: .local(localID))
    }

    public func update(_ label: Label) async throws -> Label {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard var row = Self.findRow(matching: label.id, in: rows) else { throw VikunjaError.notFound }
            row.title = label.title
            row.hexColor = label.hexColor
            try row.save(db)

            let payload = LabelCreateOrUpdatePayload(title: label.title, hexColor: label.hexColor)
            // A row that's never synced still has its original `create`
            // pending - that's the mutation this edit must update in place,
            // since `drainLabelUpdate` bails out on a row with no `remoteID` yet.
            let operation: MutationOperation = row.remoteID == nil ? .create : .update
            try Self.enqueueOrCoalesce(
                operation: operation, targetLocalID: row.localID, accountID: self.accountID, payload: payload, db: db,
            )
        }
        await triggerDrainIfOnline()
        return try await readLabel(id: label.id)
    }

    public func delete(id: EntityID) async throws {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }

            // Any other mutation still pending (or failed but retryable)
            // against this row is moot once it's being deleted.
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID && $0.targetLocalID == row.localID
                        && ($0.status == .pending || $0.status == .failed)
                }
                .forEach { try $0.delete(db) }

            guard let remoteID = row.remoteID else {
                // Never synced - nothing server-side to delete.
                try row.delete(db)
                return
            }
            let payload = LabelDeletePayload(remoteID: remoteID)
            var item = try MutationQueueRecord(
                id: nil,
                accountID: self.accountID,
                entityType: .label,
                operation: .delete,
                targetLocalID: row.localID,
                payload: Self.encode(payload),
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
        await triggerDrainIfOnline()
    }

    public func addLabel(_ labelID: Int, toTask taskID: Int) async throws {
        try await networkLabelRepository.addLabel(labelID, toTask: taskID)
        // The network call just made this true server-side, but every
        // screen reads a task's labels from `TaskRecord.labelRemoteIDs`
        // (see its doc comment), which otherwise only catches up on the
        // next `pullTasks()` - patch it now so the rest of the app shows
        // the new label immediately instead of looking stale until then.
        await updateCachedTaskLabels(taskID: taskID) { ids in
            ids.contains(labelID) ? ids : ids + [labelID]
        }
    }

    public func removeLabel(_ labelID: Int, fromTask taskID: Int) async throws {
        try await networkLabelRepository.removeLabel(labelID, fromTask: taskID)
        await updateCachedTaskLabels(taskID: taskID) { ids in
            ids.filter { $0 != labelID }
        }
    }

    private func updateCachedTaskLabels(taskID: Int, mutate: @Sendable ([Int]) -> [Int]) async {
        let accountID = accountID
        try? await localStore.write { db in
            guard var row = try TaskRecord.fetchAll(db)
                .first(where: { $0.accountID == accountID && $0.remoteID == taskID }) else { return }
            let ids = row.labelRemoteIDs.split(separator: ",").compactMap { Int($0) }
            row.labelRemoteIDs = mutate(ids).map(String.init).joined(separator: ",")
            try row.save(db)
        }
    }

    private func triggerDrainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainLabelMutations()
    }

    /// Blocks the very first read against an account's cache on a cold pull
    /// — see `OfflineProjectRepository.pullIfNeverSynced` for the full
    /// rationale (identical reasoning, one per entity).
    private func pullIfNeverSynced() async {
        let alreadyPulled = await (try? localStore.read { db in
            try SyncStateRecord.fetchAll(db).contains { $0.accountID == self.accountID && $0.entityType == .label }
        }) ?? false
        guard !alreadyPulled, await reachability.isReachable else { return }
        try? await syncEngine.pullLabels()
    }

    /// The actual local read behind a freshly written row — `create`/
    /// `update` call this instead of going through the public
    /// `fetchLabels()`/cold-pull path, for the same reason
    /// `OfflineProjectRepository.readProject` does: a pull running in
    /// between could reconcile-delete or discard that same row before the
    /// server's own response has caught up to it.
    private func readLabel(id: EntityID) async throws -> Label {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            guard !hiddenLocalIDs.contains(row.localID) else { throw VikunjaError.notFound }
            return Self.label(from: row)
        }
    }

    private static func accountRows(_ accountID: UUID, db: Database) throws -> [LabelRecord] {
        try LabelRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    private static func pendingDeleteTargetLocalIDs(accountID: UUID, db: Database) throws -> Set<UUID> {
        try Set(
            MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == accountID && $0.entityType == .label && $0.operation == .delete
                        && ($0.status == .pending || $0.status == .failed)
                }
                .map(\.targetLocalID),
        )
    }

    private static func findRow(matching id: EntityID, in rows: [LabelRecord]) -> LabelRecord? {
        switch id {
        case let .local(localID): rows.first { $0.localID == localID }
        case let .remote(remoteID): rows.first { $0.remoteID == remoteID }
        }
    }

    private static func label(from row: LabelRecord) -> Label {
        Label(id: row.remoteID.map(EntityID.remote) ?? .local(row.localID), title: row.title, hexColor: row.hexColor)
    }

    private static func enqueueOrCoalesce(
        operation: MutationOperation,
        targetLocalID: UUID,
        accountID: UUID,
        payload: some Encodable,
        db: Database,
    ) throws {
        let encoded = try Self.encode(payload)
        let existing = try MutationQueueRecord.fetchAll(db).first {
            $0.accountID == accountID && $0.entityType == .label && $0.targetLocalID == targetLocalID
                && ($0.status == .pending || $0.status == .failed) && $0.operation == operation
        }
        if var existing {
            existing.payload = encoded
            existing.status = .pending
            existing.needsConflictResolution = false
            try existing.update(db)
        } else {
            var item = MutationQueueRecord(
                id: nil,
                accountID: accountID,
                entityType: .label,
                operation: operation,
                targetLocalID: targetLocalID,
                payload: encoded,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
