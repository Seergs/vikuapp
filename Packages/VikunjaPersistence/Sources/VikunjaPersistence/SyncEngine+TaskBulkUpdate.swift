import Foundation
import GRDB
import VikunjaCore

private struct TaskBulkBatch: Sendable {
    let items: [MutationQueueRecord]
    let taskIDs: [EntityID]
    let change: TaskBulkChange
}

private struct TaskBulkCandidate: Sendable {
    let item: MutationQueueRecord
    let taskID: EntityID
    let intent: TaskBulkIntent
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

    /// A logical batch can make progress across several submissions. Only the
    /// verified, still-current subset is claimed and sent; other tasks keep
    /// their own conflicts, failures, or ordering dependencies.
    /// Returns true when this pass marked at least one new conflict.
    func drainTaskBulkBatch(_ batchID: UUID) async throws -> Bool {
        guard activeTaskBulkBatches.insert(batchID).inserted else { return false }
        defer { activeTaskBulkBatches.remove(batchID) }
        let candidates = try await localStore.read { db in
            try Self.taskBulkCandidates(batchID, accountID: self.accountID, db: db)
        }
        var ready: [TaskBulkCandidate] = []
        var conflicts: [TaskBulkCandidate] = []
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                if try await taskBulkCandidateConflicts(candidate) {
                    conflicts.append(candidate)
                } else {
                    ready.append(candidate)
                }
            } catch {
                try checkSyncInterruption(error)
                guard (error as? VikunjaError) != .offline else { throw error }
                // A task-specific verification failure must not fail siblings.
                // Nothing has been claimed or submitted yet.
                try await markFailed(candidate.item, error: error)
            }
        }
        let (batch, flaggedConflict) = try await localStore.write { [ready, conflicts] db in
            try Self.claimTaskBulkBatch(ready: ready, conflicts: conflicts, accountID: self.accountID, db: db)
        }
        guard let batch else { return flaggedConflict }
        do {
            guard let taskBulkUpdateRepository else { throw TaskBulkDrainError.missingRepository }
            try Task.checkCancellation()
            let tasks = try await taskBulkUpdateRepository.apply(batch.change, toTaskIDs: batch.taskIDs)
            try await acknowledgeTaskBulkBatch(batch, tasks: tasks)
        } catch {
            try await handleTaskBulkFailure(error, batch: batch)
        }
        return flaggedConflict
    }

    private func taskBulkCandidateConflicts(_ candidate: TaskBulkCandidate) async throws -> Bool {
        // Legacy dates are evaluated at the final transaction, against the most
        // recently observed row. Their absent field snapshots cannot be invented.
        guard let base = candidate.intent.baseFields else { return false }
        let current = try await taskRepository.fetchTask(id: candidate.taskID)
        try Task.checkCancellation()
        let fields = try await localStore.read { db in
            try TaskEditableFields.server(current, accountID: self.accountID, db: db)
        }
        return TaskEditEvaluation.compare(
            base: base, desired: base.applying(candidate.intent.change), current: fields,
        ) == .conflict
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
        if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled
            || (error as? VikunjaError) == .offline {
            do {
                try await localStore.write { db in
                    for sent in batch.items {
                        guard var item = try MutationQueueRecord.fetchOne(db, key: sent.id),
                              item.payload == sent.payload else { continue }
                        item.status = sent.status
                        try item.update(db)
                    }
                }
            } catch is CancellationError {
                // Suspension can prevent cleanup. Durable claims are released by
                // recoverTaskBulkUpdates before the next replay, without a failure.
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

    private static func taskBulkCandidates(
        _ batchID: UUID, accountID: UUID, db: Database,
    ) throws -> [TaskBulkCandidate] {
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID)
            .order(Column("id")).fetchAll(db)
        var candidates: [TaskBulkCandidate] = []
        for item in queue where item.entityType == .task && item.operation.isBulkTaskChange {
            let intent = try TaskBulkIntent(item: item)
            guard intent.batchID == batchID,
                  let row = try eligibleTaskBulkRow(item, queue: queue, db: db),
                  let remoteID = row.remoteID else { continue }
            if let first = candidates.first, first.intent.change != intent.change {
                throw TaskBulkDrainError.invalidPayload
            }
            candidates.append(TaskBulkCandidate(item: item, taskID: .remote(remoteID), intent: intent))
        }
        return candidates
    }

    /// FIFO is per task, never across unrelated members of a logical batch.
    private static func eligibleTaskBulkRow(
        _ item: MutationQueueRecord, queue: [MutationQueueRecord], db: Database,
    ) throws -> TaskRecord? {
        guard item.status != .inFlight, !item.needsConflictResolution,
              let row = try TaskRecord.fetchOne(db, key: item.targetLocalID),
              row.accountID == item.accountID, row.remoteID != nil else { return nil }
        let blocked = queue.contains {
            $0.entityType == .task && $0.targetLocalID == item.targetLocalID && $0.id != item.id
                && ($0.operation == .delete || $0.needsConflictResolution || $0.operation == .create
                    || (($0.id ?? 0) < (item.id ?? 0)
                        && ($0.operation.isBulkTaskChange || [.update, .moveBucket].contains($0.operation))))
        }
        return blocked ? nil : row
    }

    /// Re-read after network verification: edits, deletes, and new dependencies
    /// arriving during that read must not be claimed using an obsolete snapshot.
    private static func claimTaskBulkBatch(
        ready: [TaskBulkCandidate], conflicts: [TaskBulkCandidate], accountID: UUID, db: Database,
    ) throws -> (TaskBulkBatch?, Bool) {
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
        let byID = Dictionary(uniqueKeysWithValues: queue.compactMap { item in item.id.map { ($0, item) } })
        let conflictingIDs = Set(conflicts.compactMap(\.item.id))
        var items: [MutationQueueRecord] = []
        var taskIDs: [EntityID] = []
        var flaggedConflict = false
        for candidate in conflicts + ready {
            guard let id = candidate.item.id, var current = byID[id], current == candidate.item,
                  let row = try eligibleTaskBulkRow(current, queue: queue, db: db),
                  row.remoteID == candidate.taskID.remoteValue else { continue }
            let legacyConflict = candidate.intent.baseFields == nil
                && candidate.intent.baseUpdatedAt.map { base in
                    row.serverUpdatedAt.map { $0.timeIntervalSince(base) > 1 } ?? false
                } == true
            if conflictingIDs.contains(id) || legacyConflict {
                current.needsConflictResolution = true
                flaggedConflict = true
            } else {
                // Retain pre-claim status in the snapshot, for interrupted writes.
                items.append(current)
                taskIDs.append(candidate.taskID)
                current.status = .inFlight
            }
            try current.update(db)
        }
        guard let first = items.first else { return (nil, flaggedConflict) }
        let change = try TaskBulkIntent(item: first).change
        return (TaskBulkBatch(items: items, taskIDs: taskIDs, change: change), flaggedConflict)
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
