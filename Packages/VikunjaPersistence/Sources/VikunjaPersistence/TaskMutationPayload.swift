import Foundation
import VikunjaCore

/// The frozen "what the user wants" snapshot a queued `create`/`update`
/// replays against the server — see `ProjectCreateOrUpdatePayload`'s doc
/// comment for why this is captured once rather than read live from
/// `TaskRecord` at drain time.
struct TaskCreateOrUpdatePayload: Codable, Equatable, Sendable {
    var title: String
    var description: String?
    var isDone: Bool
    var dueDate: Date?
    var priority: Int
    /// The owning project's local id — resolved to a remote id at drain
    /// time the same way `ProjectCreateOrUpdatePayload.parentProjectLocalID`
    /// is, so a task queued under a project that's also only local-so-far
    /// still has somewhere to point until both sync.
    var projectLocalID: UUID
    /// This task's `serverUpdatedAt` as of when the mutation was queued —
    /// the conflict check's baseline. `nil` for a `create` (nothing on the
    /// server yet to conflict with).
    var baseUpdatedAt: Date?
    /// Optional so payloads queued before reminders were persisted still
    /// decode; `nil` means the task had no reminders.
    var reminders: [TaskReminder]?
    /// Optional for queues written before Kanban support.
    var kanbanDestination: KanbanCreationDestination?
    /// Missing in legacy payloads: retain their local work on rejection.
    var kanbanCreatedOnline: Bool?
}

/// What a queued `delete` needs to address the row server-side, since the
/// local row may already be gone by drain time.
struct TaskDeletePayload: Codable, Equatable, Sendable {
    var remoteID: Int
}

/// What a queued `addLabel`/`removeLabel` needs to resolve the label side at
/// drain time, the same way `TaskCreateOrUpdatePayload.projectLocalID` does
/// for a task's project — a label attached while it's still only local-so-far
/// (not yet synced) waits for its own create to resolve to a real remote id
/// before this op can fire, same dependency-ordering pattern as a sub-project
/// under a parent that's also only local-so-far. The task side is addressed
/// by the queue item's own `targetLocalID`, so it isn't repeated here.
struct TaskLabelMutationPayload: Codable, Equatable, Sendable {
    var labelLocalID: UUID
}

/// What a queued `addRelation`/`removeRelation` needs to resolve the other
/// task at drain time - same dependency-ordering reasoning as
/// `TaskLabelMutationPayload`, except *both* sides can be only local-so-far
/// here (a relation can be queued between two tasks created offline in the
/// same session), not just the referenced side. The task side is addressed
/// by the queue item's own `targetLocalID`, so only the other task and the
/// relation kind are carried here.
struct TaskRelationMutationPayload: Codable, Equatable, Sendable {
    var kind: RelationKind
    var otherTaskLocalID: UUID
}

struct KanbanCreationDestination: Codable, Equatable, Sendable {
    var viewID: Int
    var bucketID: Int
}

/// Each task retains its own queue row; a shared batch ID defines one atomic
/// server request. Local IDs resolve only after pending task creations finish.
struct TaskCompletionPayload: Codable, Equatable, Sendable {
    var batchID: UUID
    var isDone: Bool
    /// Frozen across pulls; only our own acknowledged writes rebase this value.
    var baseUpdatedAt: Date?
}

/// Same batching and baseline rules as `TaskCompletionPayload`.
struct TaskDueDatePayload: Codable, Equatable, Sendable {
    var batchID: UUID
    var dueDate: Date
    /// Frozen across pulls; only our own acknowledged writes rebase this value.
    var baseUpdatedAt: Date?
}

/// One queued bulk row decoded independently of its stored payload type, so
/// the bulk drain handles every `TaskBulkChange` the same way. Each change
/// keeps its own operation and payload type, which leaves queues written by
/// earlier versions decodable.
struct TaskBulkIntent: Equatable, Sendable {
    var batchID: UUID
    var change: TaskBulkChange
    var baseUpdatedAt: Date?

    init(batchID: UUID, change: TaskBulkChange, baseUpdatedAt: Date?) {
        self.batchID = batchID
        self.change = change
        self.baseUpdatedAt = baseUpdatedAt
    }

    init(item: MutationQueueRecord) throws {
        switch item.operation {
        case .setCompletion:
            let payload = try KanbanLocalMutations.decode(TaskCompletionPayload.self, item: item)
            self.init(
                batchID: payload.batchID, change: .completion(isDone: payload.isDone),
                baseUpdatedAt: payload.baseUpdatedAt,
            )
        case .setDueDate:
            let payload = try KanbanLocalMutations.decode(TaskDueDatePayload.self, item: item)
            self.init(
                batchID: payload.batchID, change: .dueDate(payload.dueDate),
                baseUpdatedAt: payload.baseUpdatedAt,
            )
        case .create, .update, .delete, .addLabel, .removeLabel, .addRelation, .removeRelation, .moveBucket:
            throw VikunjaError.decoding("Queue item \(item.operation.rawValue) is not a bulk task change.")
        }
    }

    var operation: MutationOperation {
        MutationOperation(bulkChange: change)
    }

    func encodedPayload() throws -> String {
        switch change {
        case let .completion(isDone):
            try KanbanLocalMutations.encode(
                TaskCompletionPayload(batchID: batchID, isDone: isDone, baseUpdatedAt: baseUpdatedAt),
            )
        case let .dueDate(dueDate):
            try KanbanLocalMutations.encode(
                TaskDueDatePayload(batchID: batchID, dueDate: dueDate, baseUpdatedAt: baseUpdatedAt),
            )
        }
    }
}

extension MutationOperation {
    /// Operations which are drained in batches through the bulk endpoint.
    static let bulkTaskChanges: [MutationOperation] = [.setCompletion, .setDueDate]

    var isBulkTaskChange: Bool {
        Self.bulkTaskChanges.contains(self)
    }

    init(bulkChange: TaskBulkChange) {
        switch bulkChange {
        case .completion: self = .setCompletion
        case .dueDate: self = .setDueDate
        }
    }
}
