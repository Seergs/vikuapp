import Foundation

/// The optimistic-with-rollback task mutations every task-list screen needs —
/// toggling completion, deleting, moving to another project — with the toast
/// wording and haptic policy in one place instead of copied onto each list
/// view model (Today, Calendar, the project overview, Search).
///
/// The view model owns its list; this only performs the request and reports
/// what the list should show afterwards. It never touches the list itself, so
/// it works the same whether the caller keeps a plain `[VikunjaTask]` or a
/// list wrapped in a load-state enum.
@MainActor
public struct TaskListMutator {
    /// Turns an error from a failed mutation into user-facing toast copy.
    /// Injected because each feature phrases `VikunjaError` its own way
    /// (`VikunjaError+DisplayMessage`), and that wording is deliberately kept
    /// per-feature rather than shared.
    public typealias ErrorMessageProvider = @Sendable (Error) -> String

    private let repository: TaskRepositoryProtocol
    private let toastPresenter: ToastPresenting
    private let hapticPresenter: HapticFeedbackPresenting
    private let errorMessage: ErrorMessageProvider

    public init(
        repository: TaskRepositoryProtocol,
        toastPresenter: ToastPresenting,
        hapticPresenter: HapticFeedbackPresenting = NoopHapticFeedback(),
        errorMessage: @escaping ErrorMessageProvider = { $0.localizedDescription },
    ) {
        self.repository = repository
        self.toastPresenter = toastPresenter
        self.hapticPresenter = hapticPresenter
        self.errorMessage = errorMessage
    }

    /// Persists a completion flip the caller has already applied optimistically.
    /// Plays a success haptic when the task is now done, and returns the task
    /// the list should show: the server's copy on success, `original` on
    /// failure (a silent rollback — a rejected toggle isn't worth a toast).
    public func persistToggleDone(
        flipped: VikunjaTask,
        original: VikunjaTask,
    ) async -> VikunjaTask {
        if flipped.isDone {
            hapticPresenter.play(.success)
        }
        do {
            return try await repository.update(flipped)
        } catch {
            return original
        }
    }

    /// Deletes `task`. Returns `true` (with a success toast) when the caller
    /// should drop it from the list, `false` (with an error toast) when the
    /// request failed and the row should stay.
    public func delete(_ task: VikunjaTask) async -> Bool {
        do {
            try await repository.delete(id: task.id)
            toastPresenter.show("Task deleted", style: .success)
            return true
        } catch {
            toastPresenter.show(errorMessage(error), style: .error)
            return false
        }
    }

    /// Moves `task` to `destination`. Returns `true` (with a success toast)
    /// when the caller should drop it from the list — it no longer belongs on
    /// a screen scoped to its old project — or `false` (with an error toast)
    /// on failure.
    public func move(_ task: VikunjaTask, to destination: Project) async -> Bool {
        var updated = task
        updated.projectID = destination.id
        do {
            _ = try await repository.update(updated)
            toastPresenter.show("Task moved to \(destination.title)", style: .success)
            return true
        } catch {
            toastPresenter.show(errorMessage(error), style: .error)
            return false
        }
    }
}
