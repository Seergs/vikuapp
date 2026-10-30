import Foundation
import GRDB
import VikunjaCore

/// Stored codes keep recovery copy localizable when the pending queue is read.
enum KanbanCreationFailure: String, Error {
    case capacity = "kanban.create.capacity"
    case destination = "kanban.create.destination"
    case rejected = "kanban.create.rejected"
    case ambiguous = "kanban.create.ambiguous"

    var allowsRecovery: Bool {
        self != .ambiguous
    }

    var message: String {
        switch self {
        case .capacity:
            String(
                localized: "This column is full. Retry, choose another column, or delete this local task.",
                bundle: .module,
            )
        case .destination:
            String(
                localized: "Column unavailable. Choose another column or delete this local task.",
                bundle: .module,
            )
        case .rejected:
            String(
                localized: "Creation rejected. Check capacity or permissions, retry, or choose another column.",
                bundle: .module,
            )
        case .ambiguous:
            String(
                localized: "Creation unconfirmed. Check server before recreating this task. Automatic retry is paused.",
                bundle: .module,
            )
        }
    }
}

extension SyncEngine {
    /// Runs at the beginning of a drain. An interrupted POST cannot be replayed safely.
    func recoverKanbanCreations() async throws {
        let active = activeKanbanCreations
        try await localStore.write { db in
            for var item in try MutationQueueRecord.filter(Column("accountID") == self.accountID).fetchAll(db)
                where item.entityType == .task && item.operation == .create && item.status == .inFlight {
                guard let id = item.id, !active.contains(id),
                      try Self.kanbanPayload(item)?.kanbanDestination != nil else { continue }
                item.status = .failed
                item.needsConflictResolution = true
                item.lastError = KanbanCreationFailure.ambiguous.rawValue
                try item.update(db)
            }
        }
    }

    func drainKanbanCreation(
        _ item: MutationQueueRecord, task: VikunjaTask, destination: KanbanCreationDestination,
    ) async throws -> DrainOutcome {
        guard let id = item.id, let repository = bucketRepository,
              await capabilityProvider.supports(.apiV2) else {
            try await blockKanbanCreation(item, failure: .destination)
            return .skipped
        }
        guard activeKanbanCreations.insert(id).inserted else { return .skipped }
        defer { activeKanbanCreations.remove(id) }
        let claimed: Bool
        do {
            claimed = try await claimKanbanCreation(item, destination: destination)
        } catch {
            try await blockKanbanCreation(item, failure: .destination)
            return .skipped
        }
        guard claimed else { return .skipped }
        do {
            guard let projectID = task.projectID.remoteValue else { throw VikunjaError.notFound }
            let created = try await repository.createTask(task, bucketID: destination.bucketID, projectID: projectID)
            try await applyTaskPushResult(created, deleting: item)
            return .pushed
        } catch {
            if (error as? VikunjaError) == .bucketFull {
                try await handleFullCreation(item, task: task)
                return .skipped
            }
            let failure: KanbanCreationFailure = switch error {
            case VikunjaError.notFound, VikunjaError.unauthorized: .rejected
            case let VikunjaError.server(_, statusCode) where (400 ..< 500).contains(statusCode): .rejected
            default: .ambiguous
            }
            try await blockKanbanCreation(item, failure: failure)
            return .skipped
        }
    }

    private func handleFullCreation(_ item: MutationQueueRecord, task: VikunjaTask) async throws {
        let notify = try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id),
                  current.accountID == self.accountID,
                  current.status == .inFlight,
                  let payload = try Self.kanbanPayload(current)
            else { return false }
            let row = try TaskRecord.fetchOne(db, key: current.targetLocalID)
            guard row?.remoteID == nil else { return false }
            // An explicit deletion during the request also cancels the rejected POST.
            if row == nil || payload.kanbanCreatedOnline == true {
                try RejectedLocalTaskRemoval.remove(current.targetLocalID, accountID: self.accountID, db: db)
                return row != nil
            }
            // Legacy/offline creations and explicit recoveries retain their local work.
            current.status = .failed
            current.needsConflictResolution = true
            current.retryCount += 1
            current.lastError = KanbanCreationFailure.capacity.rawValue
            try current.update(db)
            return false
        }
        if notify {
            await onKanbanCreationRejected(accountID)
        }
        // Refresh capacity after rejection. Failed downloads retain the prior usable board.
        try? await pullKanban(projectID: task.projectID)
    }

    private func claimKanbanCreation(
        _ item: MutationQueueRecord, destination: KanbanCreationDestination,
    ) async throws -> Bool {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id),
                  current.payload == item.payload, !current.needsConflictResolution,
                  current.status == .pending || current.status == .failed
            else { return false }
            guard let task = try TaskRecord.fetchOne(db, key: item.targetLocalID), task.remoteID == nil,
                  let project = try ProjectRecord.fetchOne(db, key: task.projectLocalID),
                  project.accountID == self.accountID, !project.isArchived,
                  let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
                  .filter(Column("remoteID") == destination.viewID).fetchOne(db),
                  view.lastCompletePullAt != nil, view.mode == "manual", view.filterQuery.isEmpty,
                  try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                  .filter(Column("remoteID") == destination.bucketID).fetchOne(db) != nil
            else { throw VikunjaError.notFound }
            current.status = .inFlight
            try current.update(db)
            return true
        }
    }

    private func blockKanbanCreation(_ item: MutationQueueRecord, failure: KanbanCreationFailure) async throws {
        try await localStore.write { db in
            guard var current = try MutationQueueRecord.fetchOne(db, key: item.id) else { return }
            current.status = .failed
            current.needsConflictResolution = true
            current.retryCount += 1
            current.lastError = failure.rawValue
            try current.update(db)
        }
    }

    private static func kanbanPayload(_ item: MutationQueueRecord) throws -> TaskCreateOrUpdatePayload? {
        guard let payload = item.payload else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TaskCreateOrUpdatePayload.self, from: Data(payload.utf8))
    }
}
