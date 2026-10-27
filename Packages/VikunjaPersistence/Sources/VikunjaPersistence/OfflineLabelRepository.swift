import Foundation
import GRDB
import VikunjaCore

/// Local-first `LabelRepositoryProtocol` — same shape as
/// `OfflineProjectRepository`, minus the hierarchy and conflict-detection
/// machinery projects need: a label is just a title and a color, with
/// nothing else depending on it syncing in any particular order.
///
/// `addLabel`/`removeLabel` (attaching a label to a task) are queued here
/// too, against the *task* side (`entityType: .task`, same table
/// `drainTaskMutations()` already drains) — the label side is resolved at
/// drain time via `TaskLabelMutationPayload.labelLocalID`, the same
/// dependency-ordering pattern a sub-project's parent uses. Either side
/// still being only local-so-far simply defers the item to the next drain
/// pass, instead of silently dropping the attach like the pre-Slice-4
/// pass-through did.
public actor OfflineLabelRepository: LabelRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncEngine: SyncEngine
    private let reachability: ReachabilityMonitoring

    public init(
        localStore: LocalStore,
        accountID: UUID,
        syncEngine: SyncEngine,
        reachability: ReachabilityMonitoring,
    ) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncEngine = syncEngine
        self.reachability = reachability
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

    public func addLabel(_ labelID: EntityID, toTask taskID: EntityID) async throws {
        try await enqueueTaskLabelMutation(.addLabel, labelID: labelID, taskID: taskID)
        await triggerTaskDrainIfOnline()
    }

    public func removeLabel(_ labelID: EntityID, fromTask taskID: EntityID) async throws {
        try await enqueueTaskLabelMutation(.removeLabel, labelID: labelID, taskID: taskID)
        await triggerTaskDrainIfOnline()
    }

    /// Queues the attach/detach against the task's own row (`entityType:
    /// .task`, same table `drainTaskMutations()` already drains) rather than
    /// the label's - a task is the thing this mutation is fundamentally
    /// about, and `TaskRecord.labelRemoteIDs` (the cache every screen reads)
    /// lives there. The label side is just a reference, resolved at drain
    /// time via `payload.labelLocalID`.
    private func enqueueTaskLabelMutation(_ operation: MutationOperation, labelID: EntityID, taskID: EntityID) async throws {
        try await localStore.write { db in
            guard let taskRow = try Self.findTaskRow(matching: taskID, accountID: self.accountID, db: db) else {
                throw VikunjaError.notFound
            }
            let labelRows = try Self.accountRows(self.accountID, db: db)
            guard let labelRow = Self.findRow(matching: labelID, in: labelRows) else {
                throw VikunjaError.notFound
            }
            let payload = TaskLabelMutationPayload(labelLocalID: labelRow.localID)
            var item = try MutationQueueRecord(
                id: nil,
                accountID: self.accountID,
                entityType: .task,
                operation: operation,
                targetLocalID: taskRow.localID,
                payload: Self.encode(payload),
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
    }

    private static func findTaskRow(matching id: EntityID, accountID: UUID, db: Database) throws -> TaskRecord? {
        let rows = try TaskRecord.fetchAll(db).filter { $0.accountID == accountID }
        switch id {
        case let .local(localID): return rows.first { $0.localID == localID }
        case let .remote(remoteID): return rows.first { $0.remoteID == remoteID }
        }
    }

    private func triggerDrainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainLabelMutations()
    }

    private func triggerTaskDrainIfOnline() async {
        guard await reachability.isReachable else { return }
        try? await syncEngine.drainTaskMutations()
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
