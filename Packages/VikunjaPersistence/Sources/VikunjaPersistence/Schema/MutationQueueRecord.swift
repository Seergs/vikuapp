import Foundation
import GRDB

/// Which local table a queued mutation targets. Grows by one case per
/// entity as later slices add their own offline support (Label, VikunjaTask,
/// ...) - the `mutationQueueItem` table itself needs no schema change.
enum MutationEntityType: String, Codable, Sendable {
    case project
    case filter
    case label
    case task
    /// A comment on a task. Uses the shared `create`/`update`/`delete`
    /// operations, with the comment's own local id as `targetLocalID` and
    /// its task carried in the payload — unlike labels/relations, which are
    /// queued against the `.task` row itself.
    case comment
}

/// What a queued mutation does to its target. `create`/`update`/`delete`
/// cover whole-object writes; a sub-resource op (e.g. labels-on-task) can
/// add its own case later without a schema change. `addLabel`/`removeLabel`
/// are resolved via `TaskLabelMutationPayload`; `addRelation`/`removeRelation`
/// via `TaskRelationMutationPayload`. Both pairs are queued against a `.task`
/// item.
enum MutationOperation: String, Codable, Sendable {
    case create
    case update
    case delete
    case addLabel
    case removeLabel
    case addRelation
    case removeRelation
}

enum MutationStatus: String, Codable, Sendable {
    case pending
    case inFlight
    case failed
}

/// Row shape of the `mutationQueueItem` table: one pending write to replay
/// against the server once reachable, entity-agnostic by design (see
/// `DatabaseMigrations`). `payload` is the JSON-encoded full target state for
/// `create`/`update` (the API is full-object-replace, not a partial diff);
/// for `delete` it carries whatever the server needs to address the row
/// (its `remoteID`), since the local row may already be gone by drain time.
struct MutationQueueRecord: Codable, Equatable, Sendable {
    var id: Int64?
    var accountID: UUID
    var entityType: MutationEntityType
    var operation: MutationOperation
    var targetLocalID: UUID
    var payload: String?
    var createdAt: Date
    var retryCount: Int
    var lastError: String?
    var status: MutationStatus
    /// Set when a queued `update` conflicts with a newer server-side edit
    /// observed by the most recent pull — draining skips it until a person
    /// resolves it, which isn't built yet.
    var needsConflictResolution: Bool
    /// Snapshot of the row's `serverUpdatedAt` at the moment this mutation
    /// was enqueued. Belongs to the mutation (not the mutable row) so pulls
    /// that refresh a protected row cannot invalidate the conflict baseline.
    var baseUpdatedAt: Date?
}

extension MutationQueueRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "mutationQueueItem"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
