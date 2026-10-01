@testable import Kanban
import VikunjaCore

final class FakeBucketRepository: BucketRepositoryProtocol, @unchecked Sendable {
    var buckets: [KanbanBucket] = []
    var fetchError: VikunjaError?
    var moveError: VikunjaError?
    var createError: VikunjaError?
    private(set) var movedTaskIDs: [(taskID: Int, bucketID: Int)] = []
    private(set) var createdTasks: [(task: VikunjaTask, bucketID: Int)] = []
    /// What `moveTask`/`createTask` hand back on success — defaults to
    /// reflecting the requested change, like a real server would.
    var moveResult: ((Int, Int) -> VikunjaTask)?
    var createResult: ((VikunjaTask, Int) -> VikunjaTask)?

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        if let fetchError {
            throw fetchError
        }
        return buckets
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int) async throws -> VikunjaTask {
        if let moveError {
            throw moveError
        }
        movedTaskIDs.append((taskID, toBucketID))
        if let moveResult {
            return moveResult(taskID, toBucketID)
        }
        let task = buckets.flatMap(\.tasks).first { $0.id == taskID }
        return task ?? VikunjaTask(id: taskID, title: "", projectID: projectID)
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        if let createError {
            throw createError
        }
        createdTasks.append((task, bucketID))
        if let createResult {
            return createResult(task, bucketID)
        }
        return VikunjaTask(id: 99, title: task.title, projectID: projectID)
    }
}

final class FakeToastPresenter: ToastPresenting, @unchecked Sendable {
    private(set) var shownMessages: [(message: String, style: ToastStyle)] = []

    func show(_ message: String, style: ToastStyle) {
        shownMessages.append((message, style))
    }
}

final class FakeHapticPresenter: HapticFeedbackPresenting, @unchecked Sendable {
    private(set) var played: [HapticStyle] = []

    func play(_ style: HapticStyle) {
        played.append(style)
    }
}
