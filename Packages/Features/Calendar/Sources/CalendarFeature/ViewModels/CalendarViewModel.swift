import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the Calendar screen: the account's tasks across every project, which
/// `CalendarView` lays out on a month grid by due date. Like the Today screen,
/// nothing scopes the fetch to one project — every project's tasks are pulled
/// and merged.
@MainActor
@Observable
public final class CalendarViewModel {
    public private(set) var tasks: [VikunjaTask] = []
    /// Looked up per row/dot for the project color, since a task only carries
    /// its `projectID`.
    public private(set) var projectsByID: [Int: Project] = [:]
    public private(set) var loadState: ScreenLoadState<Void> = .idle

    public var isLoading: Bool {
        loadState == .loading
    }

    private let taskLoader: AccountTaskLoader
    private let mutator: TaskListMutator

    public init(
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
    ) {
        self.taskLoader = AccountTaskLoader(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
        )
        // The Calendar screen surfaces no toasts of its own yet — only
        // `persistToggleDone` is used, which never toasts.
        self.mutator = TaskListMutator(
            repository: taskRepository,
            toastPresenter: NoopToastPresenter(),
            hapticPresenter: hapticPresenter,
        )
    }

    /// Skips the `.loading` transition when content is already loaded (a
    /// pull-to-refresh), so the grid doesn't swap out for a spinner mid-refresh
    /// — same reasoning as `TodayViewModel.load()`.
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

    /// Flips a task's completion state, persists it, and rolls the local flip
    /// back if the server rejects it — so a failed request never leaves a row
    /// showing a state the server doesn't have.
    public func toggleDone(_ task: VikunjaTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var flipped = task
        flipped.isDone.toggle()
        tasks[index] = flipped
        tasks[index] = await mutator.persistToggleDone(flipped: flipped, original: task)
    }
}
