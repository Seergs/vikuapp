import Foundation
import GRDB
import VikunjaCore

enum KanbanMoveFailure: String {
    case rejected = "kanban.move.rejected"
    case conflict = "kanban.move.conflict"
    case ambiguous = "kanban.move.ambiguous"
    var message: String {
        switch self {
        case .rejected:
            String(
                localized: "Move rejected. Check column capacity and access, then choose another column.",
                bundle: .module,
            )
        case .conflict:
            String(
                localized: "The server placement changed. Check the server, then choose another column.",
                bundle: .module,
            )
        case .ambiguous:
            String(localized: "Move unconfirmed. Check the server before choosing another column.", bundle: .module)
        }
    }
}

extension SyncEngine {
    func recoverKanbanMoves() async throws {
        let active = activeKanbanMoves
        try await localStore.write { db in
            for var item in try MutationQueueRecord.filter(Column("accountID") == self.accountID).fetchAll(db)
                where item.operation == .moveBucket && item.status == .inFlight && !active.contains(item.id ?? -1) {
                item.status = .failed
                item.needsConflictResolution = true
                item.lastError = KanbanMoveFailure.ambiguous.rawValue
                try item.update(db)
            }
        }
    }

    func drainKanbanMove(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        let payload = try KanbanLocalMutations.decode(KanbanMovePayload.self, item: item)
        guard let id = item.id, activeKanbanMoves.insert(id).inserted else { return .skipped }
        defer { activeKanbanMoves.remove(id) }
        guard let repository = bucketRepository, await capabilityProvider.supports(.apiV2) else {
            try await failKanbanMove(item, reason: .rejected)
            return .skipped
        }
        let task = try await localStore.read { db in try TaskRecord.fetchOne(db, key: item.targetLocalID) }
        guard let task else {
            try await localStore.write { db in try MutationQueueRecord.deleteOne(db, key: item.id) }
            return .skipped
        }
        guard let remoteID = task.remoteID else { return .deferred }
        let projectID = try await localStore.read { db in
            try ProjectRecord.fetchOne(db, key: payload.projectLocalID)?.remoteID
        }
        guard let projectID else { return .deferred }
        // This read has no side effects. Network failures here remain safe to retry.
        // A remote change between this read and the PUT still follows the server's write ordering.
        let snapshot = try await repository.downloadBoard(projectID: projectID, viewID: payload.viewID)
        guard snapshot.mode == "manual", snapshot.filterQuery.isEmpty,
              snapshot.buckets.contains(where: { $0.id == payload.bucketID }),
              let source = snapshot.buckets.first(where: { $0.tasks.contains { $0.id == .remote(remoteID) } }) else {
            try await failKanbanMove(item, reason: .rejected)
            return .skipped
        }
        guard payload.overrideRemotePlacement == true
            || source.id == payload.baselineBucketID || source.id == payload.bucketID else {
            try await failKanbanMove(item, reason: .conflict)
            return .conflicted
        }
        guard try await claimKanbanMove(item) else { return .skipped }
        do {
            let response: VikunjaTask = if source.id == payload.bucketID {
                try requireTask(source.tasks.first { $0.id == .remote(remoteID) })
            } else {
                try await repository.moveTask(
                    taskID: remoteID,
                    toBucketID: payload.bucketID,
                    projectID: projectID,
                    viewID: payload.viewID,
                )
            }
            try await applyKanbanMove(response, item: item, payload: payload)
            return .pushed
        } catch {
            let reason: KanbanMoveFailure = switch error {
            case VikunjaError.notFound, VikunjaError.unauthorized: .rejected
            case let VikunjaError.server(_, code) where (400 ..< 500).contains(code): .rejected
            default: .ambiguous
            }
            try await failKanbanMove(item, reason: reason, baseline: reason == .rejected ? source.id : nil)
            return .skipped
        }
    }

    private func claimKanbanMove(_ item: MutationQueueRecord) async throws -> Bool {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id),
                  current.payload == item.payload, current.status != .inFlight, !current.needsConflictResolution
            else { return false }
            let deleted = try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("targetLocalID") == item.targetLocalID).fetchAll(db).contains { $0.operation == .delete }
            let payload = try KanbanLocalMutations.decode(KanbanMovePayload.self, item: current)
            let task = try TaskRecord.fetchOne(db, key: current.targetLocalID)
            guard !deleted, task?.accountID == self.accountID, task?.projectLocalID == payload.projectLocalID else {
                try current.delete(db)
                return false
            }
            current.status = .inFlight
            try current.update(db)
            return true
        }
    }

    private func failKanbanMove(
        _ item: MutationQueueRecord, reason: KanbanMoveFailure, baseline: Int? = nil,
    ) async throws {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id), current.payload == item.payload
            else { return }
            current.status = .failed
            current.needsConflictResolution = true
            current.lastError = reason.rawValue
            current.retryCount += 1
            try current.update(db)
            if let baseline {
                let sent = try KanbanLocalMutations.decode(KanbanMovePayload.self, item: item)
                let queued = try MutationQueueRecord.filter(Column("targetLocalID") == item.targetLocalID).fetchAll(db)
                for var next in queued
                    where next.operation == .moveBucket && next.id != item.id && next.status == .pending {
                    var payload = try KanbanLocalMutations.decode(KanbanMovePayload.self, item: next)
                    if payload.viewID == sent.viewID {
                        payload.baselineBucketID = baseline
                        next.payload = try KanbanLocalMutations.encode(payload)
                        try next.update(db)
                    }
                }
            }
        }
    }

    private func applyKanbanMove(_ response: VikunjaTask, item: MutationQueueRecord, payload: KanbanMovePayload) async throws {
        try await localStore.write { db in
            guard let current = try MutationQueueRecord.fetchOne(db, key: item.id), current.payload == item.payload
            else { return }
            var others = try MutationQueueRecord.filter(Column("accountID") == self.accountID)
                .filter(Column("targetLocalID") == item.targetLocalID).fetchAll(db).filter { $0.id != item.id }
            for obsolete in others where obsolete.operation == .moveBucket && obsolete.status == .failed
                && (obsolete.id ?? 0) < (item.id ?? 0) {
                if try KanbanLocalMutations.decode(KanbanMovePayload.self, item: obsolete).viewID == payload.viewID {
                    try obsolete.delete(db)
                    others.removeAll { $0.id == obsolete.id }
                }
            }
            let view = try KanbanViewRecord.filter(Column("projectLocalID") == payload.projectLocalID)
                .filter(Column("remoteID") == payload.viewID).fetchOne(db)
            let actualBucket = response.isDone == payload.isDone ? payload.bucketID
                : (response.isDone ? view?.doneBucketID : view?.defaultBucketID)
            if var row = try TaskRecord.fetchOne(db, key: item.targetLocalID) {
                row.serverUpdatedAt = response.updated
                if others.allSatisfy({ ![.create, .update, .moveBucket, .delete].contains($0.operation) }) {
                    row.isDone = response.isDone
                    row.dueDate = response.dueDate
                    if let view, let bucket = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                        .filter(Column("remoteID") == actualBucket).fetchOne(db) {
                        try KanbanAssignmentRecord(
                            accountID: self.accountID,
                            projectLocalID: row.projectLocalID,
                            viewLocalID: view.localID,
                            bucketLocalID: bucket.localID,
                            taskLocalID: row.localID,
                            position: KanbanLocalMutations.nextPosition(bucket.localID, db: db),
                        ).save(db)
                    }
                }
                try row.update(db)
            }
            for var next in others where next.operation == .moveBucket && next.status != .inFlight {
                var body = try KanbanLocalMutations.decode(KanbanMovePayload.self, item: next)
                if body.viewID == payload.viewID, let actualBucket {
                    body.baselineBucketID = actualBucket
                    next.payload = try KanbanLocalMutations.encode(body)
                    try next.update(db)
                }
            }
            for var edit in others where edit.operation == .update && edit.status != .inFlight {
                var body = try KanbanLocalMutations.decode(TaskCreateOrUpdatePayload.self, item: edit)
                body.baseUpdatedAt = response.updated
                edit.baseUpdatedAt = response.updated
                edit.payload = try KanbanLocalMutations.encode(body)
                try edit.update(db)
            }
            try current.delete(db)
        }
    }
}

private func requireTask(_ task: VikunjaTask?) throws -> VikunjaTask {
    guard let task else { throw VikunjaError.notFound }
    return task
}
