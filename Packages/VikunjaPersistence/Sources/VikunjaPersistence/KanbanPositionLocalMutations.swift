import Foundation
import GRDB
import VikunjaCore

struct KanbanPositionPayload: Codable, Sendable {
    let projectLocalID: UUID
    let viewID: Int
    let bucketID: Int
    let placement: KanbanTaskPlacement
    var originalPosition: Double
    var submittedPosition: Double?
    var confirmed: Bool = false
    var serverPosition: Double?
    var serverBucketID: Int?
    var serverIsDone: Bool?
}

enum KanbanPositionLocalMutations {
    struct Request {
        let taskID: EntityID
        let projectID: EntityID
        let viewID: Int
        let bucketID: Int
        let placement: KanbanTaskPlacement
    }

    static func reorder(_ request: Request, accountID: UUID, db: Database) throws -> Bool {
        let (taskID, projectID, viewID, bucketID, placement) = (
            request.taskID, request.projectID, request.viewID, request.bucketID, request.placement,
        )
        guard let task = try TaskRecord.filter(Column("accountID") == accountID).fetchAll(db).first(where: {
            taskID == .local($0.localID) || $0.remoteID.map(EntityID.remote) == taskID
        }), let project = try ProjectRecord.fetchOne(db, key: task.projectLocalID), !project.isArchived,
        projectID == .local(project.localID) || project.remoteID.map(EntityID.remote) == projectID,
        let view = try KanbanViewRecord.filter(Column("projectLocalID") == project.localID)
        .filter(Column("remoteID") == viewID).fetchOne(db), KanbanLocalMutations.supports(view),
        let bucket = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
        .filter(Column("remoteID") == bucketID).fetchOne(db),
        var assignment = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
        .filter(Column("taskLocalID") == task.localID).fetchOne(db), assignment.bucketLocalID == bucket.localID
        else { throw VikunjaError.notFound }
        let queue = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
        guard !queue.contains(where: {
            $0.targetLocalID == task.localID && ($0.operation == .delete
                || ($0.operation == .create && $0.needsConflictResolution))
        }) else { throw VikunjaError.notFound }
        let previous = try queue.filter {
            $0.operation == .setTaskPosition && $0.targetLocalID == task.localID && $0.status != .inFlight
        }.filter { try payload($0).viewID == viewID }
        let deleted = Set(queue.filter { $0.operation == .delete }.map(\.targetLocalID))
        let assignments = try KanbanAssignmentRecord.filter(Column("bucketLocalID") == bucket.localID)
            .order(Column("position"), Column("taskLocalID")).fetchAll(db).filter { !deleted.contains($0.taskLocalID) }
        let edge = placement == .top ? assignments.first : assignments.last
        guard edge?.taskLocalID != task.localID || !previous.isEmpty else { return false }
        var command = KanbanPositionPayload(
            projectLocalID: project.localID, viewID: viewID, bucketID: bucketID, placement: placement,
            originalPosition: assignment.position,
        )
        if let first = previous.first {
            command.originalPosition = try payload(first).originalPosition
        }
        assignment.position = try placement
            .position(among: assignments.filter { $0.taskLocalID != task.localID }.map(\.position))
        try assignment.update(db)
        for item in previous {
            try item.delete(db)
        }
        // Insert a new FIFO entry: coalescing A-top, B-top, A-top in the first
        // row would incorrectly put B above A after synchronization.
        var item = try MutationQueueRecord(
            id: nil, accountID: accountID, entityType: .task, operation: .setTaskPosition,
            targetLocalID: task.localID, payload: KanbanLocalMutations.encode(command), createdAt: Date(),
            retryCount: 0, status: .pending, needsConflictResolution: false,
        )
        try item.insert(db)
        return true
    }

    static func payload(_ item: MutationQueueRecord) throws -> KanbanPositionPayload {
        try KanbanLocalMutations.decode(KanbanPositionPayload.self, item: item)
    }

    /// Reapply pending relative intent after a download changes the numeric scale.
    static func reapply(view: KanbanViewRecord, db: Database) throws {
        let queue = try MutationQueueRecord.filter(Column("accountID") == view.accountID)
            .order(Column("id")).fetchAll(db)
        let deleted = Set(queue.filter { $0.operation == .delete }.map(\.targetLocalID))
        for item in queue where item.operation == .setTaskPosition && !deleted.contains(item.targetLocalID) {
            let command = try payload(item)
            guard command.projectLocalID == view.projectLocalID, command.viewID == view.remoteID,
                  var assignment = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
                  .filter(Column("taskLocalID") == item.targetLocalID).fetchOne(db),
                  let bucket = try KanbanBucketRecord.fetchOne(db, key: assignment.bucketLocalID),
                  bucket.remoteID == command.bucketID else { continue }
            let peers = try KanbanAssignmentRecord.filter(Column("bucketLocalID") == bucket.localID).fetchAll(db)
                .filter { $0.taskLocalID != item.targetLocalID && !deleted.contains($0.taskLocalID) }
            assignment.position = try command.placement.position(among: peers.map(\.position))
            try assignment.update(db)
        }
    }

    static func discard(_ item: MutationQueueRecord, db: Database) throws {
        let command = try payload(item)
        guard let view = try KanbanViewRecord.filter(Column("accountID") == item.accountID)
            .filter(Column("projectLocalID") == command.projectLocalID)
            .filter(Column("remoteID") == command.viewID).fetchOne(db),
            var assignment = try KanbanAssignmentRecord.filter(Column("viewLocalID") == view.localID)
            .filter(Column("taskLocalID") == item.targetLocalID).fetchOne(db) else {
            try item.delete(db)
            return
        }
        assignment.position = command.serverPosition ?? command.originalPosition
        if let bucketID = command.serverBucketID,
           let bucket = try KanbanBucketRecord.filter(Column("viewLocalID") == view.localID)
           .filter(Column("remoteID") == bucketID).fetchOne(db) {
            assignment.bucketLocalID = bucket.localID
        }
        try assignment.update(db)
        try item.delete(db)
        let otherWrites = try MutationQueueRecord.filter(Column("accountID") == item.accountID)
            .filter(Column("targetLocalID") == item.targetLocalID).fetchAll(db)
        if let isDone = command.serverIsDone,
           !otherWrites.contains(where: { [.create, .update, .setCompletion, .moveBucket].contains($0.operation) }),
           var task = try TaskRecord.fetchOne(db, key: item.targetLocalID) {
            // Discard restores observed server placement, including completion,
            // without overriding a newer local completion or project edit.
            task.isDone = isDone
            try task.update(db)
        }
        try reapply(view: view, db: db)
    }
}

extension OfflineKanbanBoardRepository: KanbanTaskOrderingProtocol {
    public func reorderTask(
        taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int, placement: KanbanTaskPlacement,
    ) async throws {
        let changed = try await localStore.write { db in
            try KanbanPositionLocalMutations.reorder(
                .init(taskID: taskID, projectID: projectID, viewID: viewID, bucketID: bucketID, placement: placement),
                accountID: accountID, db: db,
            )
        }
        if changed {
            await syncRequester.requestSync()
        }
    }
}
