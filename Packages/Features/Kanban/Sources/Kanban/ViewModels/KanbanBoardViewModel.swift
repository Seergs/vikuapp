import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Reads repository snapshots; explicit refresh owns downloads for the selected board source.
@MainActor
@Observable
public final class KanbanBoardViewModel {
    public let project: Project
    public private(set) var buckets: [KanbanBucket] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    public private(set) var hasSnapshot = false
    public private(set) var supportsWrites = false
    public private(set) var supportsTaskCreation = false
    public private(set) var requiresConnection = false
    public private(set) var isRefreshing = false
    public var isLoading: Bool {
        loadState == .loading
    }

    public private(set) var needsProjectSync = false

    private var viewID: Int?
    private let repository: KanbanBoardRepositoryProtocol
    private let trigger: SyncTriggering
    private let synchronization: LocalScreenSync
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting
    // Local cache reads must not settle an in-flight download.
    private var missingSnapshotState: ScreenLoadState<Void>?
    private var loadVersion = 0
    private var isStarting = false
    private var isObserving = false
    private var pendingActions: Set<EntityID> = []

    public init(
        project: Project, repository: KanbanBoardRepositoryProtocol,
        syncTrigger: SyncTriggering, localData: LocalDataObserving,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
    ) {
        self.project = project
        self.repository = repository
        self.trigger = syncTrigger
        self.synchronization = LocalScreenSync(
            trigger: syncTrigger, localData: localData, toastPresenter: toastPresenter,
        )
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
    }

    public func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await load()
        guard !Task.isCancelled, !needsProjectSync else { return }
        await refresh()
    }

    public func observeLocalChanges() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        await synchronization.observe { await self.load() }
    }

    public func load() async {
        loadVersion += 1
        let version = loadVersion
        if !hasSnapshot, missingSnapshotState == nil {
            loadState = .loading
        }
        do {
            let snapshot = try await repository.fetchBoard(projectID: project.id, viewID: viewID)
            guard version == loadVersion, !Task.isCancelled else { return }
            switch snapshot {
            case .waitingForProject, .unavailable:
                needsProjectSync = snapshot == .waitingForProject
                hasSnapshot = false
                supportsWrites = false
                supportsTaskCreation = false
                buckets = []
                if needsProjectSync {
                    loadState = .loaded
                } else {
                    loadState = isRefreshing ? .loading : (missingSnapshotState ?? .loading)
                }
            case let .available(board):
                needsProjectSync = false
                viewID = board.viewID
                buckets = board.buckets
                hasSnapshot = true
                supportsWrites = board.supportsWrites
                supportsTaskCreation = board.supportsTaskCreation
                requiresConnection = board.requiresConnection
                loadState = .loaded
            }
        } catch {
            guard version == loadVersion, !Task.isCancelled else { return }
            if hasSnapshot {
                show(error)
            } else {
                let failure: ScreenLoadState<Void> = .failure(message(error))
                missingSnapshotState = failure
                loadState = failure
            }
        }
    }

    public func refresh() async {
        guard !isRefreshing, !needsProjectSync else { return }
        isRefreshing = true
        if !hasSnapshot {
            loadState = .loading
        }
        defer {
            isRefreshing = false
            if !hasSnapshot, !needsProjectSync, loadState == .loading {
                let settledState = missingSnapshotState ?? .idle
                missingSnapshotState = settledState
                loadState = settledState
            }
        }
        do {
            try await trigger.refresh(scope: .kanban(projectID: project.id))
            guard !Task.isCancelled else { return }
            // An online response without a board is not an offline-cache miss.
            missingSnapshotState = .failure(message(VikunjaError.notFound))
            await load()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            await load()
            if hasSnapshot {
                show(error)
            } else {
                missingSnapshotState = (error as? VikunjaError) == .offline
                    ? .loaded : .failure(message(error))
                loadState = missingSnapshotState ?? .idle
            }
        }
    }

    public func moveTask(_ task: VikunjaTask, to bucket: KanbanBucket) async {
        await moveTask(taskID: task.id, to: bucket)
    }

    func moveTask(taskID: EntityID, to bucket: KanbanBucket) async {
        let source = buckets.first { $0.tasks.contains { $0.id == taskID } }
        let previousDone = source?.tasks.first { $0.id == taskID }?.isDone
        guard supportsWrites, let viewID, source?.id != bucket.id,
              let current = buckets.first(where: { $0.id == bucket.id }) else { return }
        guard !current.isFull else { show(VikunjaError.bucketFull); return }
        guard pendingActions.insert(taskID).inserted else { return }
        defer { pendingActions.remove(taskID) }
        do {
            let moved = try await repository.moveTask(
                taskID: taskID,
                projectID: project.id,
                viewID: viewID,
                bucketID: bucket.id,
            )
            if previousDone == false, moved.isDone {
                hapticPresenter.play(.success)
            }
            await load()
        } catch { show(error) }
    }

    public func toggleDone(_ task: VikunjaTask) async {
        guard let current = buckets.flatMap(\.tasks).first(where: { $0.id == task.id }) else { return }
        await setCompletion(current, isDone: !current.isDone)
    }

    /// Menus carry an explicit target state. If sync already applied that state
    /// while the menu was open, its command must not accidentally toggle it back.
    public func setCompletion(_ task: VikunjaTask, isDone: Bool) async {
        guard let current = self.task(id: task.id), current.isDone != isDone else { return }
        let target = isDone ? buckets.first { $0.isDoneBucket } : buckets.first { !$0.isDoneBucket }
        guard let target else { return }
        await moveTask(current, to: target)
    }

    /// Resolves live card fields for sheets that remain open during local updates.
    public func task(id: EntityID) -> VikunjaTask? {
        buckets.lazy.flatMap(\.tasks).first { $0.id == id }
    }

    /// Success means the repository accepted the task, including an offline local creation.
    @discardableResult
    public func createTask(title: String, in bucket: KanbanBucket) async -> Bool {
        guard supportsWrites, supportsTaskCreation, let viewID,
              let current = buckets.first(where: { $0.id == bucket.id }) else { return false }
        guard !current.isFull else { show(VikunjaError.bucketFull); return false }
        do {
            _ = try await repository.createTask(
                title: title, projectID: project.id, viewID: viewID, bucketID: bucket.id,
            )
            await load()
            return true
        } catch is CancellationError {
            return false
        } catch {
            show(error)
            return false
        }
    }

    private func message(_ error: any Error) -> String {
        (error as? VikunjaError)?.displayMessage ?? error.localizedDescription
    }

    private func show(_ error: any Error) {
        toastPresenter.show(message(error), style: (error as? VikunjaError) == .offline ? .info : .error)
    }
}
