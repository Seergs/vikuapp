import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Queries committed local data. Network work belongs to the account synchronization worker.
@MainActor
@Observable
public final class KanbanBoardViewModel {
    public let project: Project
    public private(set) var buckets: [KanbanBucket] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    public private(set) var hasSnapshot = false
    public private(set) var supportsWrites = false
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
        if !hasSnapshot, loadState.failureMessage == nil {
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
                buckets = []
                if loadState.failureMessage == nil {
                    loadState = .loaded
                }
            case let .available(board):
                needsProjectSync = false
                viewID = board.viewID
                buckets = board.buckets
                hasSnapshot = true
                supportsWrites = board.supportsOfflineWrites
                loadState = .loaded
            }
        } catch {
            guard version == loadVersion, !Task.isCancelled else { return }
            if hasSnapshot {
                show(error)
            } else {
                loadState = .failure(message(error))
            }
        }
    }

    public func refresh() async {
        guard !isRefreshing, !needsProjectSync else { return }
        isRefreshing = true
        if !hasSnapshot {
            loadState = .loading
        }
        defer { isRefreshing = false }
        do {
            try await trigger.refresh(scope: .kanban(projectID: project.id))
            guard !Task.isCancelled else { return }
            // Permit recovery from an initial failure even when the downloaded board is empty.
            if !hasSnapshot {
                loadState = .idle
            }
            await load()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            await load()
            if hasSnapshot {
                show(error)
            } else {
                loadState = .failure(message(error))
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
              buckets.contains(where: { $0.id == bucket.id }), pendingActions.insert(taskID).inserted else { return }
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
        let target = current.isDone ? buckets.first { !$0.isDoneBucket } : buckets.first { $0.isDoneBucket }
        guard let target else { return }
        await moveTask(current, to: target)
    }

    public func createTask(title: String, in bucket: KanbanBucket) async {
        guard supportsWrites, let viewID, buckets.contains(where: { $0.id == bucket.id }) else { return }
        do {
            _ = try await repository.createTask(
                title: title, projectID: project.id, viewID: viewID, bucketID: bucket.id,
            )
            await load()
        } catch { show(error) }
    }

    private func message(_ error: any Error) -> String {
        (error as? VikunjaError)?.displayMessage ?? error.localizedDescription
    }

    private func show(_ error: any Error) {
        toastPresenter.show(message(error), style: (error as? VikunjaError) == .offline ? .info : .error)
    }
}
