import Foundation
import GRDB
import VikunjaCore

/// A snapshot of the locally cached tasks and projects for one account, shaped
/// for read-only consumers such as the widgets. Labels and relations are
/// intentionally omitted: widgets only render core task fields, and resolving
/// them would make every widget refresh do the full repository assembly.
public struct LocalTaskSnapshot: Sendable {
    public let tasks: [VikunjaTask]
    public let projects: [Project]
    public let lastPulledAt: Date?

    public init(tasks: [VikunjaTask], projects: [Project], lastPulledAt: Date?) {
        self.tasks = tasks
        self.projects = projects
        self.lastPulledAt = lastPulledAt
    }
}

/// Reads the offline cache without triggering a pull or touching the network.
/// This is the fallback the widget extensions use when their own API request
/// fails, replacing the old App Group JSON snapshots.
public struct LocalTaskSnapshotReader: Sendable {
    private let localStore: LocalStore

    public init(localStore: LocalStore) {
        self.localStore = localStore
    }

    /// - Parameter accountID: the active account, or `nil` when the widget
    ///   cannot reach the keychain. In the latter case the store is only
    ///   readable when it contains exactly one account's data.
    public func loadSnapshot(accountID: UUID?) async throws -> LocalTaskSnapshot? {
        try await localStore.read { db in
            guard let resolvedAccountID = try Self.resolveAccountID(accountID, db: db) else {
                return nil
            }

            let projectRows = try ProjectRecord.fetchAll(db).filter { $0.accountID == resolvedAccountID }
            let projectsByLocalID = Dictionary(uniqueKeysWithValues: projectRows.map { ($0.localID, $0) })
            let hiddenTaskLocalIDs = try Self.pendingDeleteTaskLocalIDs(
                accountID: resolvedAccountID, db: db,
            )
            // Offline-created tasks have no stable id the widget can deep-link
            // to or toggle via a remote API call, so the fallback only carries
            // rows the server has already acknowledged.
            let taskRows = try TaskRecord.fetchAll(db).filter {
                $0.accountID == resolvedAccountID
                    && $0.remoteID != nil
                    && !hiddenTaskLocalIDs.contains($0.localID)
            }
            let syncRows = try SyncStateRecord.fetchAll(db).filter { $0.accountID == resolvedAccountID }
            let lastPulledAt = syncRows.first { $0.entityType == .task }?.lastPulledAt

            guard !projectRows.isEmpty || !taskRows.isEmpty || lastPulledAt != nil else {
                return nil
            }

            let projects = projectRows.compactMap { row -> Project? in
                guard let remoteID = row.remoteID else { return nil }
                let parentID = row.parentProjectLocalID.flatMap { projectsByLocalID[$0] }
                    .map { $0.remoteID.map(EntityID.remote) ?? .local($0.localID) }
                return Project(
                    id: .remote(remoteID),
                    title: row.title,
                    description: row.description,
                    isArchived: row.isArchived,
                    isFavorite: row.isFavorite,
                    parentProjectID: parentID,
                    position: row.position,
                    hexColor: row.hexColor,
                    updated: row.serverUpdatedAt,
                )
            }
            let tasks = taskRows.compactMap { row -> VikunjaTask? in
                guard let remoteID = row.remoteID else { return nil }
                let projectID = projectsByLocalID[row.projectLocalID].flatMap { projectRow in
                    projectRow.remoteID.map(EntityID.remote)
                } ?? .local(row.projectLocalID)
                return VikunjaTask(
                    id: .remote(remoteID),
                    title: row.title,
                    description: row.description,
                    isDone: row.isDone,
                    dueDate: row.dueDate,
                    priority: VikunjaTask.Priority(rawValue: row.priority) ?? .unset,
                    projectID: projectID,
                    updated: row.serverUpdatedAt,
                )
            }

            return LocalTaskSnapshot(tasks: tasks, projects: projects, lastPulledAt: lastPulledAt)
        }
    }

    private static func resolveAccountID(_ accountID: UUID?, db: Database) throws -> UUID? {
        if let accountID {
            return accountID
        }
        let taskAccountIDs = try Set(TaskRecord.fetchAll(db).map(\.accountID))
        let projectAccountIDs = try Set(ProjectRecord.fetchAll(db).map(\.accountID))
        let syncAccountIDs = try Set(
            SyncStateRecord.fetchAll(db)
                .filter { $0.entityType == .task || $0.entityType == .project }
                .map(\.accountID),
        )
        let accountIDs = taskAccountIDs.union(projectAccountIDs).union(syncAccountIDs)
        return accountIDs.count == 1 ? accountIDs.first : nil
    }

    private static func pendingDeleteTaskLocalIDs(accountID: UUID, db: Database) throws -> Set<UUID> {
        try Set(
            MutationQueueRecord.fetchAll(db)
                .filter {
                    $0.accountID == accountID && $0.entityType == .task && $0.operation == .delete
                        && ($0.status == .pending || $0.status == .failed)
                }
                .map(\.targetLocalID),
        )
    }
}
