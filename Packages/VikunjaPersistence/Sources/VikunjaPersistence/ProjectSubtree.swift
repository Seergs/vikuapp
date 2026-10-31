import Foundation
import GRDB

/// Account-scoped traversal shared by optimistic reads and deletion replay.
/// Keep the hierarchy intact until the server confirms a delete: a pull must
/// not turn a hidden descendant into a visible root by dropping its parent.
enum ProjectSubtree {
    static func localIDs(rootIDs: Set<UUID>, rows: [ProjectRecord]) -> Set<UUID> {
        let children = Dictionary(grouping: rows, by: \.parentProjectLocalID)
        var result = rootIDs
        var pending = Array(rootIDs)
        while let parent = pending.popLast() {
            for child in children[parent] ?? [] where result.insert(child.localID).inserted {
                pending.append(child.localID)
            }
        }
        return result
    }

    /// A synced ancestor's server delete covers its whole branch. A synced
    /// project moved under an offline-only parent still needs its own delete.
    static func remoteRoots(rootID: UUID, rows: [ProjectRecord]) -> [ProjectRecord] {
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.localID, $0) })
        let children = Dictionary(grouping: rows, by: \.parentProjectLocalID)
        var pending = [rootID]
        var visited: Set<UUID> = []
        var result: [ProjectRecord] = []
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let row = rowsByID[id] else { continue }
            if row.remoteID != nil {
                result.append(row)
            } else {
                pending.append(contentsOf: (children[id] ?? []).map(\.localID))
            }
        }
        return result
    }

    static func pendingDeleteIDs(accountID: UUID, rows: [ProjectRecord], db: Database) throws -> Set<UUID> {
        let roots = try Set(MutationQueueRecord.fetchAll(db).filter {
            $0.accountID == accountID && ($0.entityType == .project || $0.entityType == .filter)
                && $0.operation == .delete
        }.map(\.targetLocalID))
        return localIDs(rootIDs: roots, rows: rows)
    }

    /// The server deletes the project's tasks and comments too. Their queued
    /// writes must not survive and later retry against entities that are gone.
    static func discardMutations(projectIDs: Set<UUID>, accountID: UUID, db: Database) throws {
        let taskIDs = try Set(TaskRecord.fetchAll(db).filter {
            $0.accountID == accountID && projectIDs.contains($0.projectLocalID)
        }.map(\.localID))
        let commentIDs = try Set(TaskCommentRecord.fetchAll(db).filter {
            $0.accountID == accountID && taskIDs.contains($0.taskLocalID)
        }.map(\.localID))
        for item in try MutationQueueRecord.fetchAll(db) where item.accountID == accountID {
            let shouldDiscard: Bool = switch item.entityType {
            case .project: projectIDs.contains(item.targetLocalID)
            case .task: taskIDs.contains(item.targetLocalID)
            case .comment: commentIDs.contains(item.targetLocalID)
            case .filter, .label: false
            }
            if shouldDiscard {
                try item.delete(db)
            }
        }
    }

    static func remove(rootID: UUID, accountID: UUID, db: Database) throws {
        let rows = try ProjectRecord.fetchAll(db).filter { $0.accountID == accountID }
        let ids = localIDs(rootIDs: [rootID], rows: rows)
        try discardMutations(projectIDs: ids, accountID: accountID, db: db)
        // Collect the full subtree before deleting anything: the schema sets
        // child parent links to NULL when a project row is removed.
        for row in rows where ids.contains(row.localID) {
            try row.delete(db)
        }
    }
}
