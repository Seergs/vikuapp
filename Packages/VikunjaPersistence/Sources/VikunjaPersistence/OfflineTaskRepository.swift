import Foundation
import GRDB
import VikunjaCore

/// Local-first `TaskRepositoryProtocol` — same shape as
/// `OfflineProjectRepository`, minus the hierarchy machinery projects need
/// (a task has no children of its own), but keeping project's conflict-
/// detection machinery, unlike `OfflineLabelRepository`: Vikunja's task API
/// exposes `updated`, so `drainTaskUpdate` has a real baseline to compare a
/// queued edit against.
public actor OfflineTaskRepository: TaskRepositoryProtocol {
    private let localStore: LocalStore
    private let accountID: UUID
    private let syncRequester: SyncRequesting

    public init(localStore: LocalStore, accountID: UUID, syncRequester: SyncRequesting) {
        self.localStore = localStore
        self.accountID = accountID
        self.syncRequester = syncRequester
    }

    public func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        try await localStore.read { db in
            let projectRows = try Self.projectRows(self.accountID, db: db)
            guard let projectLocalID = Self.resolveProjectLocalID(matching: projectID, in: projectRows) else {
                return []
            }
            let taskRows = try Self.accountRows(self.accountID, db: db)
            let rows: [TaskRecord]
            if let remoteID = projectID.remoteValue, remoteID < 0 {
                let memberships = try VirtualProjectTaskRecord.fetchAll(db)
                    .filter { $0.accountID == self.accountID && $0.projectLocalID == projectLocalID }
                    .sorted { $0.position < $1.position }
                let rowsByLocalID = Dictionary(uniqueKeysWithValues: taskRows.map { ($0.localID, $0) })
                rows = memberships.compactMap { rowsByLocalID[$0.taskLocalID] }
            } else {
                rows = taskRows.filter { $0.projectLocalID == projectLocalID }
            }
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            let context = try Self.makeAssemblyContext(accountID: self.accountID, projectRows: projectRows, db: db)
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) }
                .map { Self.task(from: $0, context: context) }
        }
    }

    public func fetchTask(id: EntityID) async throws -> VikunjaTask {
        try await readTask(id: id)
    }

    private func readTask(id: EntityID) async throws -> VikunjaTask {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            guard !hiddenLocalIDs.contains(row.localID) else { throw VikunjaError.notFound }
            let context = try Self.makeAssemblyContext(accountID: self.accountID, db: db)
            return Self.task(from: row, context: context)
        }
    }

    public func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        let localID = UUID()
        try await localStore.write { db in
            let projectRows = try Self.projectRows(self.accountID, db: db)
            guard let projectLocalID = Self.resolveProjectLocalID(matching: task.projectID, in: projectRows) else {
                throw VikunjaError.notFound
            }
            try TaskRecord(
                localID: localID,
                accountID: self.accountID,
                remoteID: nil,
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                serverUpdatedAt: nil,
            ).insert(db)
            if let row = try TaskRecord.fetchOne(db, key: localID) {
                try KanbanLocalMutations.applyCompletion(row, db: db)
            }
            try TaskReminderRecord.replace(
                for: localID, accountID: self.accountID, reminders: task.reminders, db: db,
            )
            let payload = TaskCreateOrUpdatePayload(
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                baseUpdatedAt: nil,
                reminders: task.reminders,
            )
            try Self.enqueueOrCoalesce(context: EnqueueContext(
                operation: .create,
                targetLocalID: localID,
                accountID: self.accountID,
                payload: payload,
                baseUpdatedAt: nil,
            ), db: db)
        }
        await triggerDrainIfOnline()
        return try await readTask(id: .local(localID))
    }

    public func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard var row = Self.findRow(matching: task.id, in: rows) else { throw VikunjaError.notFound }
            let projectRows = try Self.projectRows(self.accountID, db: db)
            guard let projectLocalID = Self.resolveProjectLocalID(matching: task.projectID, in: projectRows) else {
                throw VikunjaError.notFound
            }
            let projectChanged = row.projectLocalID != projectLocalID
            if projectChanged {
                try MutationQueueRecord.filter(Column("targetLocalID") == row.localID)
                    .filter(Column("operation") == MutationOperation.moveBucket.rawValue)
                    .filter(Column("status") != MutationStatus.inFlight.rawValue).deleteAll(db)
            }
            let completionChanged = row.isDone != task.isDone
            row.title = task.title
            row.description = task.description
            row.isDone = task.isDone
            row.dueDate = task.dueDate
            row.priority = task.priority.rawValue
            row.projectLocalID = projectLocalID
            try row.save(db)
            if completionChanged || projectChanged {
                try KanbanLocalMutations.applyCompletion(row, db: db)
            }
            try TaskReminderRecord.replace(
                for: row.localID, accountID: self.accountID, reminders: task.reminders, db: db,
            )

            let payload = TaskCreateOrUpdatePayload(
                title: task.title,
                description: task.description,
                isDone: task.isDone,
                dueDate: task.dueDate,
                priority: task.priority.rawValue,
                projectLocalID: projectLocalID,
                baseUpdatedAt: row.serverUpdatedAt,
                reminders: task.reminders,
            )
            // A row that's never synced still has its original `create`
            // pending - that's the mutation this edit must update in place,
            // since `drainTaskUpdate` bails out on a row with no `remoteID` yet.
            let operation: MutationOperation = row.remoteID == nil ? .create : .update
            try Self.enqueueOrCoalesce(context: EnqueueContext(
                operation: operation,
                targetLocalID: row.localID,
                accountID: self.accountID,
                payload: payload,
                baseUpdatedAt: row.serverUpdatedAt,
            ), db: db)
        }
        await triggerDrainIfOnline()
        return try await readTask(id: task.id)
    }

    public func delete(id: EntityID) async throws {
        try await localStore.write { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            guard let row = Self.findRow(matching: id, in: rows) else { throw VikunjaError.notFound }

            // Any other mutation still pending (or failed but retryable)
            // against this row, or against one of its comments (which the FK
            // cascade removes with the task), is moot once it's being
            // deleted. Without the comment ids too, a queued comment create
            // would defer forever against a task row that no longer exists.
            let commentLocalIDs = try Set(
                TaskCommentRecord.fetchAll(db)
                    .filter { $0.accountID == self.accountID && $0.taskLocalID == row.localID }
                    .map(\.localID),
            )
            try MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == self.accountID
                        && ($0.targetLocalID == row.localID || commentLocalIDs.contains($0.targetLocalID))
                        && ($0.status == .pending || $0.status == .failed)
                }
                .forEach { try $0.delete(db) }

            guard let remoteID = row.remoteID else {
                // Never synced - nothing server-side to delete.
                try row.delete(db)
                return
            }
            let payload = TaskDeletePayload(remoteID: remoteID)
            var item = try MutationQueueRecord(
                id: nil,
                accountID: self.accountID,
                entityType: .task,
                operation: .delete,
                targetLocalID: row.localID,
                payload: Self.encode(payload),
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
            )
            try item.insert(db)
        }
        await triggerDrainIfOnline()
    }

    public func searchTasks(query: String) async throws -> [VikunjaTask] {
        try await localStore.read { db in
            let rows = try Self.accountRows(self.accountID, db: db)
            let hiddenLocalIDs = try Self.pendingDeleteTargetLocalIDs(accountID: self.accountID, db: db)
            let context = try Self.makeAssemblyContext(accountID: self.accountID, db: db)
            return rows
                .filter { !hiddenLocalIDs.contains($0.localID) && $0.title.localizedCaseInsensitiveContains(query) }
                .map { Self.task(from: $0, context: context) }
        }
    }

    private func triggerDrainIfOnline() async {
        await syncRequester.requestSync()
    }

    private static func accountRows(_ accountID: UUID, db: Database) throws -> [TaskRecord] {
        try TaskRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    private static func projectRows(_ accountID: UUID, db: Database) throws -> [ProjectRecord] {
        try ProjectRecord.fetchAll(db).filter { $0.accountID == accountID }
    }

    private static func projectsByLocalID(_ projectRows: [ProjectRecord]) -> [UUID: ProjectRecord] {
        Dictionary(uniqueKeysWithValues: projectRows.map { ($0.localID, $0) })
    }

    /// Everything `task(from:context:)` needs to resolve one task row's
    /// labels and relations, gathered once per read call (`fetchTasks`/
    /// `readTask`/`searchTasks`) rather than per row.
    struct TaskAssemblyContext {
        let projectsByLocalID: [UUID: ProjectRecord]
        let labelsByRemoteID: [Int: LabelRecord]
        let labelsByLocalID: [UUID: LabelRecord]
        let pendingLabelMutations: [UUID: [(operation: MutationOperation, labelLocalID: UUID)]]
        let relationsByTaskLocalID: [UUID: [TaskRelationRecord]]
        let remindersByTaskLocalID: [UUID: [TaskReminder]]
        let pendingRelationMutations: [UUID: [PendingRelationMutation]]
        /// The other side of every entry in `pendingRelationMutations`,
        /// under the inverse kind, keyed by the *other* task's local id
        /// instead of the owner's - see `mirrorRelationMutations(_:)`.
        let pendingMirrorRelationMutations: [UUID: [PendingRelationMutation]]
        /// Every task row for this account, keyed by local id — needed to
        /// resolve a pending relation's "other task" display fields
        /// (title/isDone/project), since that task might itself still be
        /// local-only.
        let tasksByLocalID: [UUID: TaskRecord]
        let tasksByRemoteID: [Int: TaskRecord]
    }

    static func makeAssemblyContext(
        accountID: UUID, projectRows: [ProjectRecord]? = nil, db: Database,
    ) throws -> TaskAssemblyContext {
        let projectRows = try projectRows ?? Self.projectRows(accountID, db: db)
        let labelRows = try LabelRecord.fetchAll(db).filter { $0.accountID == accountID }
        let taskRows = try Self.accountRows(accountID, db: db)
        let relationRows = try TaskRelationRecord.fetchAll(db).filter { $0.accountID == accountID }
        let remindersByTaskLocalID = try TaskReminderRecord.remindersByTaskLocalID(accountID: accountID, db: db)
        let pendingRelationMutations = try Self.pendingRelationMutations(accountID: accountID, db: db)
        return try TaskAssemblyContext(
            projectsByLocalID: Self.projectsByLocalID(projectRows),
            labelsByRemoteID: Dictionary(uniqueKeysWithValues: labelRows.compactMap { row in
                row.remoteID.map { ($0, row) }
            }),
            labelsByLocalID: Dictionary(uniqueKeysWithValues: labelRows.map { ($0.localID, $0) }),
            pendingLabelMutations: Self.pendingLabelMutations(accountID: accountID, db: db),
            relationsByTaskLocalID: Dictionary(grouping: relationRows, by: \.taskLocalID),
            remindersByTaskLocalID: remindersByTaskLocalID,
            pendingRelationMutations: pendingRelationMutations,
            pendingMirrorRelationMutations: Self.mirrorRelationMutations(pendingRelationMutations),
            tasksByLocalID: Dictionary(uniqueKeysWithValues: taskRows.map { ($0.localID, $0) }),
            tasksByRemoteID: Dictionary(uniqueKeysWithValues: taskRows.compactMap { row in
                row.remoteID.map { ($0, row) }
            }),
        )
    }

    /// A task's `addLabel`/`removeLabel` queued but not yet drained -
    /// offline, or waiting on the task/label to resolve first - isn't
    /// reflected in `TaskRecord.labelRemoteIDs` yet, since
    /// `drainTaskLabelMutation` only patches that cache once the push
    /// actually succeeds. Reading it straight from the queue here means a
    /// label attached to a task that's still entirely local (neither side
    /// has a remote id) shows up immediately instead of only after both
    /// sides sync. Keyed by the task's local id (`targetLocalID`).
    private static func pendingLabelMutations(
        accountID: UUID, db: Database,
    ) throws -> [UUID: [(operation: MutationOperation, labelLocalID: UUID)]] {
        let items = try MutationQueueRecord.fetchAll(db).filter {
            $0.accountID == accountID && $0.entityType == .task
                && ($0.operation == .addLabel || $0.operation == .removeLabel)
                && ($0.status == .pending || $0.status == .failed)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [UUID: [(operation: MutationOperation, labelLocalID: UUID)]] = [:]
        for item in items {
            guard let data = item.payload?.data(using: .utf8),
                  let payload = try? decoder.decode(TaskLabelMutationPayload.self, from: data) else { continue }
            result[item.targetLocalID, default: []].append((item.operation, payload.labelLocalID))
        }
        return result
    }

    struct PendingRelationMutation {
        let operation: MutationOperation
        let kind: RelationKind
        let otherTaskLocalID: UUID
    }

    /// Same reasoning as `pendingLabelMutations`, for `addRelation`/
    /// `removeRelation` - a relation queued but not yet drained isn't
    /// reflected in the `taskRelation` cache table yet, since
    /// `drainTaskRelationMutation` only patches it once the push succeeds.
    private static func pendingRelationMutations(
        accountID: UUID, db: Database,
    ) throws -> [UUID: [PendingRelationMutation]] {
        let items = try MutationQueueRecord.fetchAll(db).filter {
            $0.accountID == accountID && $0.entityType == .task
                && ($0.operation == .addRelation || $0.operation == .removeRelation)
                && ($0.status == .pending || $0.status == .failed)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [UUID: [PendingRelationMutation]] = [:]
        for item in items {
            guard let data = item.payload?.data(using: .utf8),
                  let payload = try? decoder.decode(TaskRelationMutationPayload.self, from: data) else { continue }
            let mutation = PendingRelationMutation(
                operation: item.operation, kind: payload.kind, otherTaskLocalID: payload.otherTaskLocalID,
            )
            result[item.targetLocalID, default: []].append(mutation)
        }
        return result
    }

    /// Builds the other side of every entry in `forward` - a relation is
    /// bidirectional under paired kinds (same as `SyncEngine`'s own
    /// `patchRelationCache`), so a pending `addRelation`/`removeRelation`
    /// queued from task A's perspective must also show up on task B's own
    /// screen, under the inverse kind, before either side has even synced -
    /// otherwise B shows nothing until A's mutation drains and a pull or app
    /// restart catches B up. Keyed by the *other* task's local id.
    private static func mirrorRelationMutations(
        _ forward: [UUID: [PendingRelationMutation]],
    ) -> [UUID: [PendingRelationMutation]] {
        var result: [UUID: [PendingRelationMutation]] = [:]
        for (ownerLocalID, mutations) in forward {
            for mutation in mutations {
                let mirrored = PendingRelationMutation(
                    operation: mutation.operation, kind: Self.inverseKind(mutation.kind),
                    otherTaskLocalID: ownerLocalID,
                )
                result[mutation.otherTaskLocalID, default: []].append(mirrored)
            }
        }
        return result
    }

    /// The relation kind the other side of a pair sees once this one is
    /// created — mirrors `SyncEngine.inverseKind(_:)` (identical mapping,
    /// duplicated rather than shared since each lives on its own private
    /// type).
    private static func inverseKind(_ kind: RelationKind) -> RelationKind {
        switch kind {
        case .subtask: .parenttask
        case .parenttask: .subtask
        case .blocking: .blocked
        case .blocked: .blocking
        case .duplicateof: .duplicates
        case .duplicates: .duplicateof
        case .precedes: .follows
        case .follows: .precedes
        case .copiedfrom: .copiedto
        case .copiedto: .copiedfrom
        case .related: .related
        }
    }

    /// Target ids to hide from a read — a delete the user asked for stays
    /// hidden whether it's still pending its first attempt or failed and
    /// waiting to be retried; either way it's not coming back.
    private static func pendingDeleteTargetLocalIDs(accountID: UUID, db: Database) throws -> Set<UUID> {
        try Set(
            MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == accountID && $0.entityType == .task && $0.operation == .delete
                        && ($0.status == .pending || $0.status == .failed)
                }
                .map(\.targetLocalID),
        )
    }

    private static func findRow(matching id: EntityID, in rows: [TaskRecord]) -> TaskRecord? {
        switch id {
        case let .local(localID): rows.first { $0.localID == localID }
        case let .remote(remoteID): rows.first { $0.remoteID == remoteID }
        }
    }

    /// Resolves the task's project reference to a local id — the same
    /// `.local`/`.remote` switch `OfflineProjectRepository.resolveLocalID`
    /// uses for a sub-project's parent, just reading `project` rows instead
    /// of this actor's own table. `nil` means the project genuinely isn't
    /// known locally yet (a real ordering bug upstream, since a task's
    /// project is never optional), not just "not synced" — `.local` is
    /// checked against real rows too, not trusted blindly.
    private static func resolveProjectLocalID(matching id: EntityID, in projectRows: [ProjectRecord]) -> UUID? {
        switch id {
        case let .local(localID): projectRows.contains { $0.localID == localID } ? localID : nil
        case let .remote(remoteID): projectRows.first { $0.remoteID == remoteID }?.localID
        }
    }

    static func task(from row: TaskRecord, context: TaskAssemblyContext) -> VikunjaTask {
        let projectID = context.projectsByLocalID[row.projectLocalID]?.remoteID.map(EntityID.remote)
            ?? .local(row.projectLocalID)
        var labels = row.labelRemoteIDs
            .split(separator: ",")
            .compactMap { Int($0) }
            .compactMap { remoteID -> Label? in
                guard let labelRow = context.labelsByRemoteID[remoteID] else { return nil }
                return Label(id: .remote(remoteID), title: labelRow.title, hexColor: labelRow.hexColor)
            }
        for mutation in context.pendingLabelMutations[row.localID] ?? [] {
            guard let labelRow = context.labelsByLocalID[mutation.labelLocalID] else { continue }
            let labelID = labelRow.remoteID.map(EntityID.remote) ?? .local(labelRow.localID)
            switch mutation.operation {
            case .addLabel:
                if !labels.contains(where: { $0.id == labelID }) {
                    labels.append(Label(id: labelID, title: labelRow.title, hexColor: labelRow.hexColor))
                }
            case .removeLabel:
                labels.removeAll { $0.id == labelID }
            case .create, .update, .delete, .addRelation, .removeRelation, .moveBucket:
                break
            }
        }
        var relationsByKind = Self.confirmedRelationsByKind(for: row.localID, context: context)
        Self.applyPendingRelationMutations(
            to: &relationsByKind, mutations: context.pendingRelationMutations[row.localID] ?? [], context: context,
        )
        Self.applyPendingRelationMutations(
            to: &relationsByKind, mutations: context.pendingMirrorRelationMutations[row.localID] ?? [],
            context: context,
        )
        return VikunjaTask(
            id: row.remoteID.map(EntityID.remote) ?? .local(row.localID),
            title: row.title,
            description: row.description,
            isDone: row.isDone,
            dueDate: row.dueDate,
            priority: VikunjaTask.Priority(rawValue: row.priority) ?? .unset,
            projectID: projectID,
            labels: labels,
            subtasks: relationsByKind[.subtask] ?? [],
            dependsOn: relationsByKind[.blocked] ?? [],
            blocks: relationsByKind[.blocking] ?? [],
            otherRelations: relationsByKind.filter { ![.subtask, .blocked, .blocking].contains($0.key) },
            reminders: context.remindersByTaskLocalID[row.localID] ?? [],
            updated: row.serverUpdatedAt,
        )
    }

    /// This task's confirmed relations, using current local task fields
    /// when available, grouped by kind the way `VikunjaTask.subtasks`/`dependsOn`/
    /// `blocks`/`otherRelations` split them (mirrors `TaskMapper`'s own
    /// network-side grouping).
    private static func confirmedRelationsByKind(
        for taskLocalID: UUID, context: TaskAssemblyContext,
    ) -> [RelationKind: [TaskRelation]] {
        var result: [RelationKind: [TaskRelation]] = [:]
        for relationRow in context.relationsByTaskLocalID[taskLocalID] ?? [] {
            // Relation rows are snapshots from the last sync. Prefer the task's
            // current local state, including edits still waiting in the queue.
            // Keep the snapshot as a fallback for tasks not available locally.
            let otherTask = context.tasksByRemoteID[relationRow.otherTaskRemoteID]
            let projectID = otherTask.map { task in
                context.projectsByLocalID[task.projectLocalID]?.remoteID.map(EntityID.remote)
                    ?? .local(task.projectLocalID)
            } ?? .remote(relationRow.otherProjectRemoteID)
            let relation = TaskRelation(
                id: .remote(relationRow.otherTaskRemoteID),
                title: otherTask?.title ?? relationRow.title,
                isDone: otherTask?.isDone ?? relationRow.isDone,
                projectID: projectID,
            )
            result[relationRow.kind, default: []].append(relation)
        }
        return result
    }

    /// Overlays `mutations` (either `context.pendingRelationMutations[id]`,
    /// this task's own queued relation ops, or
    /// `context.pendingMirrorRelationMutations[id]`, the other side of
    /// someone else's) onto `relationsByKind` - same reasoning as
    /// `task(from:context:)`'s label overlay: a relation between two tasks
    /// that are still entirely local (neither side has a remote id) must
    /// show up immediately, on *both* tasks' own screens, rather than only
    /// once both sides have synced and the drain has run.
    private static func applyPendingRelationMutations(
        to relationsByKind: inout [RelationKind: [TaskRelation]],
        mutations: [PendingRelationMutation],
        context: TaskAssemblyContext,
    ) {
        for mutation in mutations {
            guard let otherTaskRow = context.tasksByLocalID[mutation.otherTaskLocalID] else { continue }
            let otherID = otherTaskRow.remoteID.map(EntityID.remote) ?? .local(otherTaskRow.localID)
            let otherProjectID = context.projectsByLocalID[otherTaskRow.projectLocalID]?.remoteID.map(EntityID.remote)
                ?? .local(otherTaskRow.projectLocalID)
            let relation = TaskRelation(
                id: otherID, title: otherTaskRow.title, isDone: otherTaskRow.isDone, projectID: otherProjectID,
            )
            switch mutation.operation {
            case .addRelation:
                var relations = relationsByKind[mutation.kind] ?? []
                if !relations.contains(where: { $0.id == otherID }) {
                    relations.append(relation)
                }
                relationsByKind[mutation.kind] = relations
            case .removeRelation:
                relationsByKind[mutation.kind]?.removeAll { $0.id == otherID }
            case .create, .update, .delete, .addLabel, .removeLabel, .moveBucket:
                break
            }
        }
    }

    /// Replaces an existing pending (or failed and still retryable) mutation
    /// of the same `operation` against `targetLocalID` in place — see
    /// `OfflineProjectRepository.enqueueOrCoalesce`'s doc comment for the
    /// full rationale (identical reasoning, one per entity).
    private struct EnqueueContext {
        let operation: MutationOperation
        let targetLocalID: UUID
        let accountID: UUID
        let payload: any Encodable
        let baseUpdatedAt: Date?
    }

    private static func enqueueOrCoalesce(context: EnqueueContext, db: Database) throws {
        var encoded = try Self.encode(context.payload)
        let existing = try MutationQueueRecord.fetchAll(db).first {
            $0.accountID == context.accountID && $0.entityType == .task && $0.targetLocalID == context.targetLocalID
                && ($0.status == .pending || $0.status == .failed
                    || (context.operation == .create && $0.status == .inFlight)) && $0.operation == context.operation
        }
        if var existing {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let previous = try existing.payload.map {
                try decoder.decode(TaskCreateOrUpdatePayload.self, from: Data($0.utf8))
            }
            let kanbanCreate = context.operation == .create && previous?.kanbanDestination != nil
            if kanbanCreate {
                var updated = try decoder.decode(TaskCreateOrUpdatePayload.self, from: Data(encoded.utf8))
                updated.kanbanDestination = previous?.kanbanDestination
                updated.kanbanCreatedOnline = previous?.kanbanCreatedOnline
                encoded = try Self.encode(updated)
            }
            existing.payload = encoded
            if !kanbanCreate || (existing.status != .inFlight && !existing.needsConflictResolution) {
                existing.status = .pending
                existing.needsConflictResolution = false
            }
            existing.baseUpdatedAt = context.baseUpdatedAt
            try existing.update(db)
        } else {
            var item = MutationQueueRecord(
                id: nil,
                accountID: context.accountID,
                entityType: .task,
                operation: context.operation,
                targetLocalID: context.targetLocalID,
                payload: encoded,
                createdAt: Date(),
                retryCount: 0,
                lastError: nil,
                status: .pending,
                needsConflictResolution: false,
                baseUpdatedAt: context.baseUpdatedAt,
            )
            try item.insert(db)
        }
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
