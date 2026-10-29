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
        loadState == .loading || (synchronization.isPreparingInitialSnapshot && tasks.isEmpty)
    }

    /// Keep an initial-sync failure visible even if a subsequent local
    /// invalidation successfully reads the still-empty cache.
    public var displayLoadState: ScreenLoadState<Void> {
        if isLoading {
            return .loading
        }
        if tasks.isEmpty, let message = synchronization.initialFailureMessage {
            return .failure(message)
        }
        return loadState
    }

    private let taskLoader: AccountTaskLoader
    private let toastPresenter: ToastPresenting
    private let mutator: TaskListMutator

    private let synchronization: LocalScreenSync
    private var loadVersion = 0

    public init(
        syncTrigger: SyncTriggering,
        localData: LocalDataObserving,
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
        toastPresenter: ToastPresenting = NoopToastPresenter(),
    ) {
        self.toastPresenter = toastPresenter
        self.synchronization = LocalScreenSync(
            trigger: syncTrigger, localData: localData, toastPresenter: toastPresenter,
        )
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
        loadVersion += 1
        let version = loadVersion
        let hadContent = loadState == .loaded
        if !hadContent {
            loadState = .loading
        }
        do {
            let result = try await taskLoader.loadAllTasks()
            guard version == loadVersion else { return }
            projectsByID = result.projectsByID
            tasks = result.tasks
            loadState = .loaded
        } catch let error as VikunjaError {
            guard version == loadVersion else { return }
            if hadContent {
                toastPresenter.show(error.displayMessage, style: .error)
            } else {
                loadState = .failure(error.displayMessage)
            }
        } catch {
            guard version == loadVersion else { return }
            if hadContent {
                toastPresenter.show(error.localizedDescription, style: .error)
            } else {
                loadState = .failure(error.localizedDescription)
            }
        }
    }

    /// Flips a task's completion state, persists it, and rolls the local flip
    /// back if the server rejects it — so a failed request never leaves a row
    /// showing a state the server doesn't have.
    public func toggleDone(_ task: VikunjaTask) async {
        loadVersion += 1
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var flipped = task
        flipped.isDone.toggle()
        tasks[index] = flipped
        let result = await mutator.persistToggleDone(flipped: flipped, original: task)
        acceptMutationResult(result, replacing: flipped)
    }

    /// Observation can reorder or remove a row while a write is suspended.
    /// Apply the result only if that same optimistic value is still visible.
    private func acceptMutationResult(_ result: VikunjaTask, replacing expected: VikunjaTask) {
        guard let index = tasks.firstIndex(where: { $0.id == expected.id }), tasks[index] == expected else { return }
        tasks[index] = result
    }

    public func start() async {
        await synchronization.start(reload: { await self.load() }, onInitialFailure: { message in
            if !tasks.isEmpty {
                toastPresenter.show(message, style: .error)
            } else {
                loadState = .failure(message)
            }
        })
    }

    public func observeLocalChanges() async {
        await synchronization.observe { await self.load() }
    }

    public func refresh() async {
        await synchronization.refresh(reload: { await self.load() })
    }
}
