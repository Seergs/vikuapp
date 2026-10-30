import Foundation
import GRDB
import VikunjaCore

struct KanbanMovePayload: Codable, Sendable, Equatable {
    var projectLocalID: UUID
    var viewID: Int
    var bucketID: Int
    var baselineBucketID: Int
    var overrideRemotePlacement: Bool?
    var isDone: Bool
}

enum KanbanLocalMutations {
    struct Request {
        let taskID: EntityID
        let projectID: EntityID
        let viewID: Int
        let bucketID: Int
    }

    static func move(_ request: Request, accountID: UUID, db: Database) throws -> (VikunjaTask, Bool) {
        guard var task = try TaskRecord.filter(Column("accountID") == accountID).fetchAll(db).first(where: {
            request.taskID == .local($0.localID) || $0.remoteID.map(EntityID.remote) == request.taskID
        }), let project = try ProjectRecord.fetchOne(db, key: task.projectLocalID), !project.isArchived,
        request.projectID == .local(project.localID) || project.remoteID.map(EntityID.remote) == request.projectID,
        let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
        .filter(Column("remoteID") == request.viewID).fetchOne(db), supports(view),
        let destination = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
        .filter(Column("remoteID") == request.bucketID).fetchOne(db),
        var assignment = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
        .filter(Column("taskLocalID") == task.localID).fetchOne(db),
        let source = try KanbanBucketRecord.fetchOne(db, key: assignment.bucketLocalID)
        else { throw VikunjaError.notFound }
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID)
            .filter(Column("targetLocalID") == task.localID).fetchAll(db)
        guard !queue.contains(where: {
            $0.operation == .delete || ($0.operation == .create && $0.needsConflictResolution)
        })
        else { throw VikunjaError.notFound }
        guard source.localID != destination.localID else {
            return try (domain(task, db: db), false)
        }
        if destination.remoteID == view.doneBucketID {
            task.isDone = true
        } else if source.remoteID == view.doneBucketID {
            task.isDone = false
        }
        try task.update(db)
        assignment.bucketLocalID = destination.localID
        assignment.position = try nextPosition(destination.localID, db: db)
        try assignment.update(db)
        try enqueueMove(KanbanMovePayload(
            projectLocalID: project.localID,
            viewID: view.remoteID,
            bucketID: destination.remoteID,
            baselineBucketID: source.remoteID,
            isDone: task.isDone,
        ), task: task, db: db)
        return try (domain(task, db: db), true)
    }

    static func supports(_ view: KanbanViewRecord) -> Bool {
        view.lastCompletePullAt != nil && view.mode == "manual"
            && view.filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func domain(_ task: TaskRecord, db: Database) throws -> VikunjaTask {
        try OfflineTaskRepository.task(
            from: task,
            context: OfflineTaskRepository.makeAssemblyContext(accountID: task.accountID, db: db),
        )
    }

    static func nextPosition(_ bucketID: UUID, db: Database) throws -> Double {
        try KanbanAssignmentRecord.filter(Column("bucketLocalID") == bucketID).fetchAll(db)
            .map(\.position).max().map { $0 + 1 } ?? 0
    }

    static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try String(data: encoder.encode(payload), encoding: .utf8) ?? ""
    }

    static func decode<T: Decodable>(_ type: T.Type, item: MutationQueueRecord) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data((item.payload ?? "").utf8))
    }

    private static func enqueueMove(_ payload: KanbanMovePayload, task: TaskRecord, db: Database) throws {
        let queue = try MutationQueueRecord.filter(Column("accountID") == task.accountID)
            .filter(Column("targetLocalID") == task.localID).fetchAll(db)
        if var creation = queue.first(where: { $0.operation == .create && $0.status == .pending }) {
            var body = try decode(TaskCreateOrUpdatePayload.self, item: creation)
            body.kanbanDestination = KanbanCreationDestination(viewID: payload.viewID, bucketID: payload.bucketID)
            body.isDone = task.isDone
            creation.payload = try encode(body)
            try creation.update(db)
            return
        }
        var updated = payload
        var mutation = queue.first { item in
            item.operation == .moveBucket && item.status != .inFlight
                && (try? decode(KanbanMovePayload.self, item: item).viewID) == payload.viewID
        } ?? MutationQueueRecord(
            id: nil,
            accountID: task.accountID,
            entityType: .task,
            operation: .moveBucket,
            targetLocalID: task.localID,
            payload: nil,
            createdAt: Date(),
            retryCount: 0,
            lastError: nil,
            status: .pending,
            needsConflictResolution: false,
        )
        if mutation.id != nil {
            let previous = try decode(KanbanMovePayload.self, item: mutation)
            updated.baselineBucketID = previous.baselineBucketID
            updated.overrideRemotePlacement = previous.overrideRemotePlacement == true
                || mutation.needsConflictResolution
        }
        for obsolete in queue where obsolete.operation == .moveBucket && obsolete.status != .inFlight
            && obsolete.id != mutation.id {
            if try decode(KanbanMovePayload.self, item: obsolete).viewID == payload.viewID {
                try obsolete.delete(db)
            }
        }
        mutation.payload = try encode(updated)
        mutation.status = .pending
        mutation.needsConflictResolution = false
        mutation.lastError = nil
        try mutation.save(db)
        // Any previously queued task edit must carry the same completion intent.
        for var edit in queue where edit.operation == .update && edit.status != .inFlight {
            var body = try decode(TaskCreateOrUpdatePayload.self, item: edit)
            body.isDone = task.isDone
            edit.payload = try encode(body)
            try edit.update(db)
        }
    }

    static func rebaseMoves(_ task: VikunjaTask, localID: UUID, db: Database) throws {
        for var item in try MutationQueueRecord.filter(Column("targetLocalID") == localID).fetchAll(db)
            where item.operation == .moveBucket && item.status != .inFlight {
            var payload = try decode(KanbanMovePayload.self, item: item)
            guard let view = try KanbanViewRecord.filter(Column("projectLocalID") == payload.projectLocalID)
                .filter(Column("remoteID") == payload.viewID).fetchOne(db) else { continue }
            if task.isDone, let doneID = view.doneBucketID {
                payload.baselineBucketID = doneID
            } else if payload.baselineBucketID == view.doneBucketID, let defaultID = view.defaultBucketID {
                payload.baselineBucketID = defaultID
            }
            item.payload = try encode(payload)
            try item.update(db)
        }
    }

    /// List/detail completion uses the task update endpoint; no redundant bucket request.
    static func applyCompletion(_ task: TaskRecord, db: Database) throws {
        let views = try KanbanViewRecord.filter(Column("projectLocalID") == task.projectLocalID).fetchAll(db)
        for view in views where supports(view) {
            let buckets = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
                .order(Column("position"), Column("remoteID")).fetchAll(db)
            let target = task.isDone ? view.doneBucketID : (view.defaultBucketID ?? buckets.first?.remoteID)
            guard let bucket = buckets.first(where: { $0.remoteID == target }) else { continue }
            let assignment = try KanbanAssignmentRecord(
                accountID: task.accountID,
                projectLocalID: task.projectLocalID,
                viewLocalID: view.localID,
                bucketLocalID: bucket.localID,
                taskLocalID: task.localID,
                position: nextPosition(bucket.localID, db: db),
            )
            try assignment.save(db)
            let queue = try MutationQueueRecord.filter(Column("accountID") == task.accountID)
                .filter(Column("targetLocalID") == task.localID).fetchAll(db)
            for var item in queue where item.status != .inFlight {
                if item.operation == .moveBucket,
                   try decode(KanbanMovePayload.self, item: item).viewID == view.remoteID {
                    try item.delete(db)
                }
                if item.operation == .create {
                    var body = try decode(TaskCreateOrUpdatePayload.self, item: item)
                    if body.kanbanDestination?.viewID == view.remoteID {
                        body.kanbanDestination?.bucketID = bucket.remoteID
                        item.payload = try encode(body)
                        try item.update(db)
                    }
                }
            }
        }
    }
}
