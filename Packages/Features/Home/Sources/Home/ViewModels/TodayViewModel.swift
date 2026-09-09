import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the Today screen: the account's tasks across every project,
/// grouped/filtered by due date in `TodayView`. Unlike `Projects`' screens,
/// there's no single project scoping the fetch — every project's tasks are
/// pulled and merged here.
@MainActor
@Observable
public final class TodayViewModel {
    public private(set) var tasks: [VikunjaTask] = []
    /// Looked up per row for the project color dot + name, since a task only
    /// carries its `projectID`.
    public private(set) var projectsByID: [Int: Project] = [:]
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Every project on the instance, for the "Move to Project" picker —
    /// loaded lazily via `loadMoveCandidates()` rather than alongside
    /// `load()`, since most visits to this screen never open that picker.
    public private(set) var allProjects: [Project] = []

    public var isLoading: Bool {
        loadState == .loading
    }

    private let taskLoader: AccountTaskLoader
    private let mutator: TaskListMutator
    private let projectRepository: ProjectRepositoryProtocol

    public init(
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
    ) {
        self.taskLoader = AccountTaskLoader(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
        )
        self.mutator = TaskListMutator(
            repository: taskRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
            errorMessage: { ($0 as? VikunjaError)?.displayMessage ?? $0.localizedDescription },
        )
        self.projectRepository = projectRepository
    }

    /// Skips the `.loading` transition when there's already loaded content
    /// (i.e. this is a pull-to-refresh): swapping the list out for a
    /// spinner mid-refresh would tear down the `List` that owns the
    /// in-flight `.refreshable` task, cancelling its request underneath it.
    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            let result = try await taskLoader.loadAllTasks()
            projectsByID = result.projectsByID
            tasks = result.tasks
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Flips a task's completion state, persists the change, and rolls the
    /// local flip back if the server rejects it — so a failed request never
    /// leaves the row showing a state the server doesn't actually have.
    public func toggleDone(_ task: VikunjaTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var flipped = task
        flipped.isDone.toggle()
        tasks[index] = flipped
        tasks[index] = await mutator.persistToggleDone(flipped: flipped, original: task)
    }

    /// Deletes a task from the server and drops it from the local list on
    /// success. Vikunja soft-deletes tasks server-side rather than cascading
    /// the delete to subtasks/relations, so nothing else in the tree needs
    /// updating here.
    public func delete(_ task: VikunjaTask) async {
        if await mutator.delete(task) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    /// Loads every project on the instance, for the "Move to Project"
    /// picker. Failures leave `allProjects` at whatever it already was.
    public func loadMoveCandidates() async {
        allProjects = await (try? projectRepository.fetchProjects()) ?? allProjects
    }

    /// Moves `task` to `destination` and drops it from the local list on
    /// success — it no longer belongs to the Today view after the move.
    public func move(_ task: VikunjaTask, to destination: Project) async {
        if await mutator.move(task, to: destination) {
            tasks.removeAll { $0.id == task.id }
        }
    }
}
