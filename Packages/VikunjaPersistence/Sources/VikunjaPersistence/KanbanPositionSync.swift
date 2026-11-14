import Foundation
import GRDB
import VikunjaCore

private struct KanbanPositionContext: Sendable {
    let item: MutationQueueRecord
    let payload: KanbanPositionPayload
    let taskID: Int
    let projectID: Int
}

extension SyncEngine {
    func recoverKanbanPositions() async throws {
        let active = activeKanbanPositions
        try await localStore.write { db in
            for var item in try MutationQueueRecord.filter(Column("accountID") == self.accountID).fetchAll(db)
                where item.operation == .setTaskPosition && !active.contains(item.id ?? -1) {
                let payload = try KanbanPositionLocalMutations.payload(item)
                guard let task = try TaskRecord.fetchOne(db, key: item.targetLocalID),
                      task.accountID == self.accountID, task.projectLocalID == payload.projectLocalID else {
                    try item.delete(db)
                    continue
                }
                if let view = try KanbanViewRecord.filter(Column("projectLocalID") == payload.projectLocalID)
                    .filter(Column("remoteID") == payload.viewID).fetchOne(db),
                    let assignment = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
                    .filter(Column("taskLocalID") == item.targetLocalID).fetchOne(db),
                    let bucket = try KanbanBucketRecord.fetchOne(db, key: assignment.bucketLocalID),
                    bucket.remoteID != payload.bucketID {
                    // A local bucket/completion command superseded this order
                    // while its request was in flight. Do not replay it there.
                    try item.delete(db)
                    continue
                }
                guard item.status == .inFlight else { continue }
                // submittedPosition survives process death. Replay reconciles the
                // snapshot before deciding whether any additional PUT is safe.
                item.status = .pending
                try item.update(db)
            }
        }
    }

    func drainKanbanPosition(_ item: MutationQueueRecord) async throws -> DrainOutcome {
        guard let id = item.id, activeKanbanPositions.insert(id).inserted else { return .skipped }
        defer { activeKanbanPositions.remove(id) }
        do {
            guard let repository = bucketRepository, await capabilityProvider.supports(.apiV2) else {
                throw VikunjaError.notFound
            }
            guard let context = try await localStore.read({ db in
                try Self.positionContext(item, accountID: self.accountID, db: db)
            }) else { return .deferred }
            return try await performPosition(context, repository: repository)
        } catch {
            try checkSyncInterruption(error)
            if let current = try await releasePosition(item, error: error) {
                try await markFailed(current, error: error)
            }
            return .skipped
        }
    }

    private enum PositionDecision {
        case acknowledge
        case conflict
        case submit(Double)
    }

    private func positionDecision(
        _ context: KanbanPositionContext,
        download: KanbanDownload,
    ) throws -> PositionDecision {
        guard download.viewID == context.payload.viewID else { throw VikunjaError.decoding("Mismatched board view") }
        guard download.mode == "manual", download.filterQuery.isEmpty else { return .conflict }
        if context.payload.confirmed {
            return .acknowledge
        }
        guard let bucket = download.buckets.first(where: { $0.tasks.contains { $0.id == .remote(context.taskID) } }),
              bucket.id == context.payload.bucketID else { return .conflict }
        let position = try context.payload.placement.position(
            in: download, taskID: context.taskID, bucketID: context.payload.bucketID,
        )
        if let submitted = context.payload.submittedPosition {
            // Reconcile an uncertain outcome before considering another PUT.
            return download.taskPositions[context.taskID] == submitted || position == nil ? .acknowledge : .conflict
        }
        return position.map(PositionDecision.submit) ?? .acknowledge
    }

    private func performPosition(
        _ context: KanbanPositionContext,
        repository: any BucketRepositoryProtocol,
    ) async throws -> DrainOutcome {
        let download = try await repository.downloadBoard(projectID: context.projectID, viewID: context.payload.viewID)
        switch try positionDecision(context, download: download) {
        case .acknowledge:
            return try await acknowledgePosition(context.item, repository: repository, projectID: context.projectID)
        case .conflict:
            try await conflictPosition(context.item, download: download)
            return .conflicted
        case let .submit(position):
            guard let claimed = try await claimPosition(context, position: position) else { return .deferred }
            let result = try await repository.setTaskPosition(
                taskID: context.taskID, viewID: context.payload.viewID, position: position,
            )
            guard result.taskID == context.taskID, result.viewID == context.payload.viewID,
                  result.position.isFinite, result.position > 0 else {
                throw VikunjaError.decoding("Invalid task position response")
            }
            guard let confirmed = try await confirmPosition(claimed) else { return .deferred }
            return try await acknowledgePosition(confirmed, repository: repository, projectID: context.projectID)
        }
    }

    private static func positionContext(
        _ item: MutationQueueRecord,
        accountID: UUID,
        db: Database,
    ) throws -> KanbanPositionContext? {
        let payload = try KanbanPositionLocalMutations.payload(item)
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
        guard let current = queue.first(where: { $0.id == item.id }), current.payload == item.payload,
              current.status != .inFlight, !current.needsConflictResolution,
              let task = try TaskRecord.fetchOne(db, key: item.targetLocalID), task.accountID == accountID,
              task.projectLocalID == payload.projectLocalID, let taskID = task.remoteID,
              let project = try ProjectRecord.fetchOne(db, key: payload.projectLocalID), !project.isArchived,
              let projectID = project.remoteID else { return nil }
        for other in queue where other.id != item.id {
            if other.targetLocalID == item.targetLocalID,
               other.operation == .delete || (other.id ?? 0) < (item.id ?? 0) {
                return nil
            }
            if other.operation == .setTaskPosition, (other.id ?? 0) < (item.id ?? 0) {
                let earlier = try KanbanPositionLocalMutations.payload(other)
                if earlier.projectLocalID == payload.projectLocalID, earlier.viewID == payload.viewID {
                    return nil
                }
            }
        }
        return KanbanPositionContext(item: current, payload: payload, taskID: taskID, projectID: projectID)
    }

    private func claimPosition(
        _ context: KanbanPositionContext,
        position: Double,
    ) async throws -> MutationQueueRecord? {
        try await localStore.write { db in
            guard let latest = try Self.positionContext(context.item, accountID: self.accountID, db: db)
            else { return nil }
            var item = latest.item
            var payload = latest.payload
            payload.submittedPosition = position
            item.payload = try KanbanLocalMutations.encode(payload)
            item.status = .inFlight
            try item.update(db)
            return item
        }
    }

    private func confirmPosition(_ item: MutationQueueRecord) async throws -> MutationQueueRecord? {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id),
                  current.payload == item.payload else { return nil }
            var payload = try KanbanPositionLocalMutations.payload(current)
            payload.confirmed = true
            current.payload = try KanbanLocalMutations.encode(payload)
            current.status = .pending
            try current.update(db)
            return current
        }
    }

    private func releasePosition(_ item: MutationQueueRecord, error: Error) async throws -> MutationQueueRecord? {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id) else { return nil }
            var payload = try KanbanPositionLocalMutations.payload(current)
            if current.status == .inFlight {
                let rejected: Bool = switch error {
                case VikunjaError.unauthorized, VikunjaError.notFound: true
                case let VikunjaError.server(_, code): (400 ..< 500).contains(code)
                default: false
                }
                if rejected {
                    payload.submittedPosition = nil
                }
                current.payload = try KanbanLocalMutations.encode(payload)
                current.status = .pending
                try current.update(db)
            }
            return current
        }
    }

    private func conflictPosition(_ item: MutationQueueRecord, download: KanbanDownload) async throws {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id),
                  current.payload == item.payload else { return }
            var payload = try KanbanPositionLocalMutations.payload(current)
            let remoteID = try TaskRecord.fetchOne(db, key: current.targetLocalID)?.remoteID
            payload.serverPosition = remoteID.flatMap { download.taskPositions[$0] }
            payload.serverBucketID = download.buckets.first { bucket in
                bucket.tasks.contains { $0.id.remoteValue == remoteID }
            }?.id
            payload.serverIsDone = download.buckets.flatMap(\.tasks).first { $0.id.remoteValue == remoteID }?.isDone
            current.payload = try KanbanLocalMutations.encode(payload)
            current.needsConflictResolution = true
            current.status = .failed
            try current.update(db)
            if var view = try KanbanViewRecord.filter(Column("projectLocalID") == payload.projectLocalID)
                .filter(Column("remoteID") == payload.viewID).fetchOne(db) {
                view.mode = download.mode
                view.filterQuery = download.filterQuery
                try view.update(db)
                try Self.acceptPositionScale(download, view: view, db: db)
                try KanbanPositionLocalMutations.reapply(view: view, db: db)
            }
        }
    }

    private func acknowledgePosition(
        _ item: MutationQueueRecord, repository: any BucketRepositoryProtocol, projectID: Int,
    ) async throws -> DrainOutcome {
        let payload = try KanbanPositionLocalMutations.payload(item)
        let readState = try await localStore.read { db in
            try KanbanReadState(accountID: self.accountID, projectID: payload.projectLocalID, db: db)
        }
        let download = try await repository.downloadBoard(projectID: projectID, viewID: payload.viewID)
        let accepted = try await localStore.write { db -> Bool in
            guard let current = try MutationQueueRecord.fetchOne(db, key: item.id), current.payload == item.payload,
                  let project = try ProjectRecord.fetchOne(db, key: payload.projectLocalID),
                  project.accountID == self.accountID, project.remoteID == projectID,
                  download.viewID == payload.viewID,
                  try readState == KanbanReadState(accountID: self.accountID, projectID: payload.projectLocalID, db: db)
            else { return false }
            try current.delete(db)
            try self.storeKanban(download, project: project, db: db)
            if let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
                .filter(Column("remoteID") == payload.viewID).fetchOne(db) {
                // A server recalculation can change every peer's numeric position.
                // Generic task edits protect fields, not the old numeric scale.
                try Self.acceptPositionScale(download, view: view, db: db)
                try KanbanPositionLocalMutations.reapply(view: view, db: db)
            }
            return true
        }
        return accepted ? .pushed : .deferred
    }

    private static func acceptPositionScale(_ download: KanbanDownload, view: KanbanViewRecord, db: Database) throws {
        let rows = try TaskRecord.filter(Column("accountID") == view.accountID).fetchAll(db)
        let byLocal = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row.remoteID.map { (row.localID, $0) }
        })
        for var assignment in try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID).fetchAll(db) {
            guard let remoteID = byLocal[assignment.taskLocalID],
                  let position = download.taskPositions[remoteID],
                  let bucket = try KanbanBucketRecord.fetchOne(db, key: assignment.bucketLocalID),
                  download.buckets
                  .contains(where: { $0.id == bucket.remoteID && $0.tasks.contains { $0.id == .remote(remoteID) } })
            else { continue }
            assignment.position = position
            try assignment.update(db)
        }
    }
}
