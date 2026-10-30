import Foundation
@testable import Kanban
import VikunjaCore

@MainActor
final class FakeBucketRepository: KanbanBoardRepositoryProtocol {
    func hasCachedKanbanSupport() async throws -> Bool {
        hasSnapshot
    }

    var buckets: [KanbanBucket] = []
    var fetchError: VikunjaError?
    var moveError: VikunjaError?
    var createError: VikunjaError?
    var hasSnapshot = true
    var waitingForProject = false
    var supportsWrites = true
    var supportsTaskCreation = true
    var requiresConnection = false
    private(set) var movedTaskIDs: [(taskID: EntityID, bucketID: Int)] = []
    private(set) var createdTasks: [(task: VikunjaTask, bucketID: Int)] = []

    func fetchBoard(projectID: EntityID, viewID: Int?) async throws -> KanbanBoardSnapshot {
        if let fetchError {
            throw fetchError
        }
        if waitingForProject {
            return .waitingForProject
        }
        guard hasSnapshot else { return .unavailable }
        return .available(KanbanBoard(
            viewID: 7,
            buckets: buckets,
            defaultBucketID: buckets.first?.id,
            supportsWrites: supportsWrites,
            lastPulledAt: Date(timeIntervalSince1970: 1_700_000_000),
            supportsTaskCreation: supportsTaskCreation, requiresConnection: requiresConnection,
        ))
    }

    func moveTask(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask {
        if let moveError {
            throw moveError
        }
        movedTaskIDs.append((taskID, bucketID))
        guard let source = buckets.firstIndex(where: { $0.tasks.contains { $0.id == taskID } }),
              let destination = buckets.firstIndex(where: { $0.id == bucketID }),
              var task = buckets[source].tasks.first(where: { $0.id == taskID }) else { throw VikunjaError.notFound }
        buckets[source].tasks.removeAll { $0.id == taskID }
        if buckets[destination].isDoneBucket {
            task.isDone = true
        } else if buckets[source].isDoneBucket {
            task.isDone = false
        }
        buckets[destination].tasks.append(task)
        return task
    }

    func createTask(title: String, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask {
        if let createError {
            throw createError
        }
        guard let destination = buckets.firstIndex(where: { $0.id == bucketID }) else { throw VikunjaError.notFound }
        let task = VikunjaTask(
            id: .local(UUID()),
            title: title,
            isDone: buckets[destination].isDoneBucket,
            projectID: projectID,
        )
        createdTasks.append((task, bucketID))
        buckets[destination].tasks.append(task)
        return task
    }
}

@MainActor
final class TestScreenSync: SyncTriggering, LocalDataObserving {
    var refreshError: VikunjaError?
    var onRefresh: (() async throws -> Void)?
    private(set) var scopes: [SyncScope] = []
    private(set) var subscriptions = 0
    private(set) var terminations = 0
    private var continuation: AsyncThrowingStream<Void, Error>.Continuation?
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {
        scopes.append(scope)
        try await onRefresh?()
        if let refreshError {
            throw refreshError
        }
    }

    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        subscriptions += 1
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(())
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.terminations += 1 }
            }
        }
    }

    func invalidate() {
        continuation?.yield(())
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
