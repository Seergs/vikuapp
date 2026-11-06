import Foundation
import GRDB
import VikunjaCore

private struct CompletionBatch: Sendable {
    let items: [MutationQueueRecord]
    let taskIDs: [EntityID]
    let isDone: Bool
}

private enum CompletionDrainError: Error {
    case missingRepository
    case invalidPayload
}

extension SyncEngine {
    /// A process can stop after claiming a batch. Its durable intent remains
    /// retryable; a batch currently running on this engine must stay claimed.
    func recoverTaskCompletions() async throws {
        let active = activeCompletionBatches
        try await localStore.write { db in
            let items = try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("operation") == MutationOperation.setCompletion.rawValue)
                .filter(Column("status") == MutationStatus.inFlight.rawValue).fetchAll(db)
            for var item in items {
                let payload = try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: item)
                if !active.contains(payload.batchID) {
                    item.status = item.lastError == nil ? .pending : .failed
                    try item.update(db)
                }
            }
            // A newer intent may arrive while an older batch is in flight.
            // Once released, an obsolete intent must not block its replacement.
            let completions = try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("operation") == MutationOperation.setCompletion.rawValue)
                .order(Column("id").desc).fetchAll(db)
            var newestTargets: Set<UUID> = []
            for item in completions {
                if !newestTargets.insert(item.targetLocalID).inserted, item.status != .inFlight {
                    try item.delete(db)
                }
            }
        }
    }

    /// Returns true when the entire batch was blocked by a newer server edit.
    func drainTaskCompletionBatch(_ batchID: UUID) async throws -> Bool {
        guard activeCompletionBatches.insert(batchID).inserted else { return false }
        defer { activeCompletionBatches.remove(batchID) }
        let (batch, conflicts) = try await localStore.write { db in
            try Self.prepareCompletionBatch(batchID, accountID: self.accountID, db: db)
        }
        if !conflicts.isEmpty {
            for item in conflicts {
                try await flagConflict(item)
            }
            return true
        }
        guard let batch else { return false }
        do {
            guard let taskBulkCompletionRepository else { throw CompletionDrainError.missingRepository }
            try Task.checkCancellation()
            let tasks = try await taskBulkCompletionRepository.setCompletion(
                taskIDs: batch.taskIDs, isDone: batch.isDone,
            )
            try await acknowledgeCompletionBatch(batch, tasks: tasks)
        } catch {
            try await handleCompletionFailure(error, batch: batch)
        }
        return false
    }

    private func acknowledgeCompletionBatch(_ batch: CompletionBatch, tasks: [VikunjaTask]) async throws {
        guard tasks.count == batch.taskIDs.count, Set(tasks.map(\.id)) == Set(batch.taskIDs) else {
            throw VikunjaError.decoding("Bulk completion response does not match the queued task IDs.")
        }
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        try await localStore.write { db in
            for (item, id) in zip(batch.items, batch.taskIDs) {
                guard let task = byID[id] else { throw CompletionDrainError.invalidPayload }
                try Self.applyTaskPushResult(task, deleting: item, db: db)
            }
        }
    }

    private func handleCompletionFailure(_ error: any Error, batch: CompletionBatch) async throws {
        if error is CancellationError || (error as? VikunjaError) == .offline {
            try await localStore.write { db in
                for sent in batch.items {
                    guard var item = try MutationQueueRecord.fetchOne(db, key: sent.id),
                          item.payload == sent.payload else { continue }
                    item.status = sent.status
                    try item.update(db)
                }
            }
            throw error
        }
        for item in batch.items {
            try await markFailed(item, error: error)
        }
    }

    private static func prepareCompletionBatch(
        _ batchID: UUID, accountID: UUID, db: Database,
    ) throws -> (CompletionBatch?, [MutationQueueRecord]) {
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
        let items = try queue.filter { item in
            guard item.entityType == .task, item.operation == .setCompletion else { return false }
            return try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: item).batchID == batchID
        }.sorted { ($0.id ?? 0) < ($1.id ?? 0) }
        guard !items.isEmpty, items.allSatisfy({ $0.status != .inFlight && !$0.needsConflictResolution }) else {
            return (nil, [])
        }
        let ids = Set(items.compactMap(\.id))
        var taskIDs: [EntityID] = []
        var hasConflict = false
        let payload = try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: items[0])
        for item in items {
            let intent = try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: item)
            guard intent.isDone == payload.isDone else { throw CompletionDrainError.invalidPayload }
            guard let row = try TaskRecord.fetchOne(db, key: item.targetLocalID), row.accountID == accountID,
                  let remoteID = row.remoteID else { return (nil, []) }
            // Preserve FIFO for earlier edits, unresolved conflicts and creates.
            let blocked = queue.contains {
                $0.entityType == .task && $0.targetLocalID == item.targetLocalID && !ids.contains($0.id ?? 0)
                    && ($0.operation == .delete || $0.needsConflictResolution
                        || $0.operation == .create
                        || (($0.id ?? 0) < (item.id ?? 0)
                            && [.update, .setCompletion, .moveBucket].contains($0.operation)))
            }
            if blocked {
                return (nil, [])
            }
            if let baseline = intent.baseUpdatedAt, let updated = row.serverUpdatedAt,
               updated.timeIntervalSince(baseline) > 1 {
                hasConflict = true
            }
            taskIDs.append(.remote(remoteID))
        }
        if hasConflict {
            return (nil, items)
        }
        for var item in items {
            item.status = .inFlight
            try item.update(db)
        }
        return (CompletionBatch(items: items, taskIDs: taskIDs, isDone: payload.isDone), [])
    }

    /// Our own successful write is the new baseline, not a server conflict.
    /// A completion acknowledgement must also preserve later full task edits.
    static func rebaseTaskCompletionIntents(
        after sent: MutationQueueRecord, updatedAt: Date?, db: Database,
    ) throws {
        let items = try MutationQueueRecord.filter(Column("accountID") == sent.accountID)
            .filter(Column("targetLocalID") == sent.targetLocalID).fetchAll(db)
        for var item in items where item.id != sent.id && !item.needsConflictResolution && item.status != .inFlight {
            if item.operation == .setCompletion {
                if sent.operation == .update, (item.id ?? 0) < (sent.id ?? 0) {
                    try item.delete(db)
                    continue
                }
                var payload = try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: item)
                payload.baseUpdatedAt = updatedAt
                item.payload = try KanbanLocalMutations.encode(payload)
                item.baseUpdatedAt = updatedAt
                try item.update(db)
            } else if item.operation == .update, [.setCompletion, .moveBucket].contains(sent.operation) {
                var payload = try KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: item)
                payload.baseUpdatedAt = updatedAt
                item.payload = try KanbanLocalMutations.encode(payload)
                item.baseUpdatedAt = updatedAt
                try item.update(db)
            }
        }
    }
}
