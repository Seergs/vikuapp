import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives a single project's Kanban board: loads that project's buckets (each
/// already populated with its tasks) and handles drag-to-move and
/// add-task-in-bucket. `project` is fixed at construction, mirroring
/// `ProjectOverviewViewModel` — a different project gets a new view model
/// rather than this one being repointed.
@MainActor
@Observable
public final class KanbanBoardViewModel {
    public let project: Project
    public private(set) var buckets: [KanbanBucket] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle

    public var isLoading: Bool {
        loadState == .loading
    }

    private let repository: BucketRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting

    public init(
        project: Project,
        repository: BucketRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
    ) {
        self.project = project
        self.repository = repository
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
    }

    /// Mirrors `ProjectOverviewViewModel.load()`'s skip-the-spinner-on-refresh
    /// behavior.
    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            buckets = try await repository.fetchBuckets(projectID: project.id)
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Moves `task` into `bucket`: applies the move locally first, then
    /// persists it, rolling the whole board back to its prior arrangement if
    /// the server rejects it — mirrors `ProjectOverviewViewModel.toggleDone`'s
    /// optimistic-then-rollback pattern. A no-op if `task` is already in
    /// `bucket` (matches the server's own idempotent handling of a re-sent
    /// bucket). Plays a success haptic when the move lands in the view's done
    /// bucket, mirroring `TaskListMutator.persistToggleDone`'s haptic on
    /// completion.
    public func moveTask(_ task: VikunjaTask, to bucket: KanbanBucket) async {
        guard let sourceIndex = buckets.firstIndex(where: { source in source.tasks.contains { $0.id == task.id } }),
              buckets[sourceIndex].id != bucket.id,
              let destinationIndex = buckets.firstIndex(where: { $0.id == bucket.id })
        else { return }

        let original = buckets
        buckets[sourceIndex].tasks.removeAll { $0.id == task.id }
        buckets[destinationIndex].tasks.append(task)

        do {
            let moved = try await repository.moveTask(taskID: task.id, toBucketID: bucket.id, projectID: project.id)
            if let index = buckets[destinationIndex].tasks.firstIndex(where: { $0.id == moved.id }) {
                buckets[destinationIndex].tasks[index] = moved
            }
            if bucket.isDoneBucket {
                hapticPresenter.play(.success)
            }
        } catch {
            buckets = original
            toastPresenter.show((error as? VikunjaError)?.displayMessage ?? error.localizedDescription, style: .error)
        }
    }

    /// Creates a task titled `title` directly in `bucket`, appending the
    /// server's copy to that bucket's tasks on success.
    public func createTask(title: String, in bucket: KanbanBucket) async {
        guard let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return }
        do {
            let created = try await repository.createTask(
                VikunjaTask(id: 0, title: title, projectID: project.id),
                bucketID: bucket.id,
                projectID: project.id,
            )
            buckets[index].tasks.append(created)
        } catch {
            toastPresenter.show((error as? VikunjaError)?.displayMessage ?? error.localizedDescription, style: .error)
        }
    }
}
