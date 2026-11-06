import Observation
import VikunjaCore

/// A selection belongs to one list presentation. Completion and deletion share
/// one busy state and report feedback once per action after local acceptance.
@MainActor
@Observable
public final class TaskBulkSelection {
    public private(set) var isSelecting = false
    public private(set) var isDeleting = false
    public private(set) var isUpdatingCompletion = false
    public var isPerformingAction: Bool {
        isDeleting || isUpdatingCompletion
    }

    public private(set) var selectedIDs: Set<EntityID> = []
    private let toastPresenter: ToastPresenting

    public init(toastPresenter: ToastPresenting) {
        self.toastPresenter = toastPresenter
    }

    public func begin() {
        guard !isPerformingAction else { return }
        selectedIDs = []
        isSelecting = true
    }

    public func reset() {
        selectedIDs = []
        isSelecting = false
    }

    public func toggle(_ id: EntityID) {
        guard isSelecting, !isPerformingAction else { return }
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }
    }

    public func selectAll(_ tasks: [VikunjaTask]) {
        guard isSelecting, !isPerformingAction else { return }
        selectedIDs = Set(tasks.map(\.id))
    }

    public func reconcile(with tasks: [VikunjaTask]) {
        guard !isPerformingAction else { return }
        selectedIDs.formIntersection(tasks.map(\.id))
    }

    /// A single target for a homogeneous selection, or nil when the user must
    /// choose explicitly between completing and reopening a mixed selection.
    public func completionTarget(visibleTasks: [VikunjaTask]) -> Bool? {
        let tasks = selectedTasks(in: visibleTasks)
        if tasks.allSatisfy({ !$0.isDone }) {
            return true
        }
        if tasks.allSatisfy(\.isDone) {
            return false
        }
        return nil
    }

    private func selectedTasks(in visibleTasks: [VikunjaTask]) -> [VikunjaTask] {
        var seen: Set<EntityID> = []
        return visibleTasks.filter { selectedIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    /// The local repository accepts the entire completion intent atomically.
    /// Keep selection on failure; synchronization failures remain in Pending Sync.
    public func setCompletion(
        visibleTasks: [VikunjaTask],
        isDone: Bool,
        perform: ([VikunjaTask]) async throws -> Void,
    ) async {
        guard isSelecting, !isPerformingAction, !Task.isCancelled else { return }
        reconcile(with: visibleTasks)
        let selected = selectedTasks(in: visibleTasks)
        guard !selected.isEmpty else { return }
        isUpdatingCompletion = true
        defer { isUpdatingCompletion = false }
        do {
            try await perform(selected)
            reset()
            let count = selected.count
            let message = isDone
                ? String(localized: "\(count) tasks marked as completed", bundle: .module)
                : String(localized: "\(count) tasks marked as pending", bundle: .module)
            toastPresenter.show(message, style: .success)
        } catch is CancellationError {
            // No accepted write: keep the selection available to retry.
        } catch {
            toastPresenter.show(
                String(localized: "Couldn’t update selected tasks. Try again.", bundle: .module),
                style: .error,
            )
        }
    }

    /// Freeze the visible selection before the first suspension. Successful
    /// deletions are never retried; failures and unattempted items stay selected.
    /// Leaving the list clears the selection even if accepted writes finish later.
    public func delete(
        visibleTasks: [VikunjaTask],
        perform: (VikunjaTask) async -> Bool,
    ) async {
        guard isSelecting, !isPerformingAction else { return }
        reconcile(with: visibleTasks)
        let tasks = selectedTasks(in: visibleTasks)
        guard !tasks.isEmpty else { return }
        isDeleting = true
        var deletedCount = 0
        for task in tasks {
            guard !Task.isCancelled else { break }
            if await perform(task) {
                deletedCount += 1
                selectedIDs.remove(task.id)
            }
        }
        isDeleting = false
        if selectedIDs.isEmpty {
            isSelecting = false
        }
        let remainingCount = tasks.count - deletedCount
        if remainingCount > 0 {
            toastPresenter.show(
                String(localized: "\(remainingCount) tasks were not deleted. Try again.", bundle: .module),
                style: .error,
            )
        } else {
            toastPresenter.show(
                String(localized: "\(deletedCount) tasks deleted", bundle: .module),
                style: .success,
            )
        }
    }
}
