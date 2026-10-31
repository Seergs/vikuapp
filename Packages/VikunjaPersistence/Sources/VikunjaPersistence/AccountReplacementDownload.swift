import Foundation
import GRDB
import VikunjaCore

extension SyncEngine {
    /// Pull into a private store. Any partial result is disposable until every phase succeeds.
    func downloadReplacement(original: AccountSnapshot) async throws {
        try Task.checkCancellation()
        try await pullProjects()
        try Task.checkCancellation()
        try await pullFilterQueries()
        try Task.checkCancellation()
        try await pullLabels()
        try Task.checkCancellation()
        try await pullTasks()

        // Restore already cached boards and threads, including a thread whose last
        // visible comment was deleted locally. Other detail resources remain demand-loaded.
        var threadIDs = Set(original.comments.map(\.taskLocalID))
        for item in original.mutations where item.entityType == .comment {
            if let payload = item.payload?.data(using: .utf8),
               let target = try? JSONDecoder().decode(CommentTarget.self, from: payload) {
                threadIDs.insert(target.taskLocalID)
            }
        }
        for id in threadIDs {
            try Task.checkCancellation()
            try await pullComments(taskID: .local(id))
        }
        for id in Set(original.kanbanViews.map(\.projectLocalID)) {
            try Task.checkCancellation()
            let stillExists = try await localStore.read { db in
                try ProjectRecord.fetchOne(db, key: id) != nil
            }
            if stillExists {
                try await pullKanban(projectID: .local(id))
            }
        }
        try Task.checkCancellation()
    }
}

private struct CommentTarget: Decodable {
    let taskLocalID: UUID
}
