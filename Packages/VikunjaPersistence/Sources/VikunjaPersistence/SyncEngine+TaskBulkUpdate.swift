import Foundation
import GRDB
import VikunjaCore

private struct TaskBulkBatch: Sendable {
    let items: [MutationQueueRecord]
    let taskIDs: [EntityID]
    let change: TaskBulkChange
}

private enum TaskBulkDrainError: Error {
    case missingRepository
    case invalidPayload
}

extension SyncEngine {
    /// A process can stop after claiming a batch. Its durable intent remains
    /// retryable; a batch currently running on this engine must stay claimed.
    func recoverTaskBulkUpdates() async throws {
        let active = activeTaskBulkBatches
        try await localStore.write { db in
            let items = try Self.bulkQueueItems(accountID: self.accountID, db: db)
            for var item in items where item.status == .inFlight {
                if try !active.contains(TaskBulkIntent(item: item).batchID) {
                    item.status = item.lastError == nil ? .pending : .failed
                    try item.update(db)
                }
            }
            // A newer intent may arrive while an older batch is in flight.
            // Once released, an obsolete intent must not block its replacement.
            // Each kind of change only replaces the same kind for that task.
            var newest: Set<String> = []
            for item in items.sorted(by: { ($0.id ?? 0) > ($1.id ?? 0) }) {
                let key = "\(item.targetLocalID)/\(item.operation.rawValue)"
                if !newest.insert(key).inserted, item.status != .inFlight {
                    try item.delete(db)
                }
            }
        }
    }

    /// Returns true when the entire batch was blocked by a newer server edit.
    func drainTaskBulkBatch(_ batchID: UUID) async throws -> Bool {
        guard activeTaskBulkBatches.insert(batchID).inserted else { return false }
        defer { activeTaskBulkBatches.remove(batchID) }
        let (batch, conflicts) = try await localStore.write { db in
            try Self.prepareTaskBulkBatch(batchID, accountID: self.accountID, db: db)
        }
        if !conflicts.isEmpty {
            for item in conflicts {
                try await flagConflict(item)
            }
            return true
        }
        guard let batch else { return false }
        do {
            guard let taskBulkUpdateRepository else { throw TaskBulkDrainError.missingRepository }
            try Task.checkCancellation()
            if try await taskBulkBatchConflicts(batch) {
                try await localStore.write { db in
                    for sent in batch.items {
                        guard var item = try MutationQueueRecord.fetchOne(db, key: sent.id),
                              item.payload == sent.payload else { continue }
                        item.status = sent.status
                        item.needsConflictResolution = true
                        try item.update(db)
                    }
                }
                return true
            }
            let tasks = try await taskBulkUpdateRepository.apply(batch.change, toTaskIDs: batch.taskIDs)
            try await acknowledgeTaskBulkBatch(batch, tasks: tasks)
        } catch {
            try await handleTaskBulkFailure(error, batch: batch)
        }
        return false
    }

    private func taskBulkBatchConflicts(_ batch: TaskBulkBatch) async throws -> Bool {
        for (item, id) in zip(batch.items, batch.taskIDs) {
            let intent = try TaskBulkIntent(item: item)
            guard let base = intent.baseFields else { continue }
            let current = try await taskRepository.fetchTask(id: id)
            try Task.checkCancellation()
            let fields = try await localStore.read { db in
                try TaskEditableFields.server(current, accountID: self.accountID, db: db)
            }
            if case .conflict = TaskEditEvaluation.compare(
                base: base, desired: base.applying(intent.change), current: fields,
            ) {
                return true
            }
        }
        return false
    }

    private func acknowledgeTaskBulkBatch(_ batch: TaskBulkBatch, tasks: [VikunjaTask]) async throws {
        guard tasks.count == batch.taskIDs.count, Set(tasks.map(\.id)) == Set(batch.taskIDs) else {
            throw VikunjaError.decoding("Bulk update response does not match the queued task IDs.")
        }
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        try await localStore.write { db in
            for (item, id) in zip(batch.items, batch.taskIDs) {
                guard let task = byID[id] else { throw TaskBulkDrainError.invalidPayload }
                try Self.applyTaskPushResult(task, deleting: item, db: db)
            }
        }
    }

    private func handleTaskBulkFailure(_ error: any Error, batch: TaskBulkBatch) async throws {
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

    private static func bulkQueueItems(accountID: UUID, db: Database) throws -> [MutationQueueRecord] {
        try MutationQueueRecord.filter(Column("accountID") == accountID)
            .filter(MutationOperation.bulkTaskChanges.map(\.rawValue).contains(Column("operation")))
            .fetchAll(db)
    }

    private static func prepareTaskBulkBatch(
        _ batchID: UUID, accountID: UUID, db: Database,
    ) throws -> (TaskBulkBatch?, [MutationQueueRecord]) {
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
        let items = try queue.filter { item in
            guard item.entityType == .task, item.operation.isBulkTaskChange else { return false }
            return try TaskBulkIntent(item: item).batchID == batchID
        }.sorted { ($0.id ?? 0) < ($1.id ?? 0) }
        guard !items.isEmpty, items.allSatisfy({ $0.status != .inFlight && !$0.needsConflictResolution }) else {
            return (nil, [])
        }
        let ids = Set(items.compactMap(\.id))
        var taskIDs: [EntityID] = []
        var hasConflict = false
        let first = try TaskBulkIntent(item: items[0])
        for item in items {
            let intent = try TaskBulkIntent(item: item)
            guard intent.change == first.change else { throw TaskBulkDrainError.invalidPayload }
            guard let row = try TaskRecord.fetchOne(db, key: item.targetLocalID), row.accountID == accountID,
                  let remoteID = row.remoteID else { return (nil, []) }
            // Preserve FIFO for earlier edits, unresolved conflicts and creates.
            let blocked = queue.contains {
                $0.entityType == .task && $0.targetLocalID == item.targetLocalID && !ids.contains($0.id ?? 0)
                    && ($0.operation == .delete || $0.needsConflictResolution
                        || $0.operation == .create
                        || (($0.id ?? 0) < (item.id ?? 0)
                            && ($0.operation.isBulkTaskChange || [.update, .moveBucket].contains($0.operation))))
            }
            if blocked {
                return (nil, [])
            }
            if intent.baseFields == nil, let baseline = intent.baseUpdatedAt, let updated = row.serverUpdatedAt,
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
        return (TaskBulkBatch(items: items, taskIDs: taskIDs, change: first.change), [])
    }

    /// Our own successful write is the new baseline, not a server conflict.
    /// A bulk acknowledgement must also preserve later full task edits.
    static func rebaseTaskBulkIntents(
        after sent: MutationQueueRecord, task: VikunjaTask, db: Database,
    ) throws {
        let fields = try TaskEditableFields.server(task, accountID: sent.accountID, db: db)
        let items = try MutationQueueRecord.filter(Column("accountID") == sent.accountID)
            .filter(Column("targetLocalID") == sent.targetLocalID).fetchAll(db)
        for var item in items where item.id != sent.id && !item.needsConflictResolution && item.status != .inFlight {
            if item.operation.isBulkTaskChange {
                // A full update carries every field a bulk change can set, so
                // it supersedes older bulk intents for the same task.
                if sent.operation == .update, (item.id ?? 0) < (sent.id ?? 0) {
                    try item.delete(db)
                    continue
                }
                var intent = try TaskBulkIntent(item: item)
                intent.baseUpdatedAt = task.updated
                intent.baseFields = fields
                item.payload = try intent.encodedPayload()
                item.baseUpdatedAt = task.updated
                try item.update(db)
            } else if item.operation == .update, sent.operation.isBulkTaskChange || sent.operation == .moveBucket {
                var payload = try KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: item)
                payload.baseUpdatedAt = task.updated
                payload.baseFields = fields
                item.payload = try KanbanLocalMutations.encode(payload)
                item.baseUpdatedAt = task.updated
                try item.update(db)
            }
        }
    }
}
