import Observation
import VikunjaCore

/// A selection belongs to one list presentation. Deletion uses the same
/// local-first repository operation as an individual task, without per-row feedback.
@MainActor
@Observable
public final class TaskBulkSelection {
    public private(set) var isSelecting = false
    public private(set) var isDeleting = false
    public private(set) var selectedIDs: Set<EntityID> = []
    private let toastPresenter: ToastPresenting

    public init(toastPresenter: ToastPresenting) {
        self.toastPresenter = toastPresenter
    }

    public func begin() {
        guard !isDeleting else { return }
        selectedIDs = []
        isSelecting = true
    }

    public func reset() {
        selectedIDs = []
        isSelecting = false
    }

    public func toggle(_ id: EntityID) {
        guard isSelecting, !isDeleting else { return }
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }
    }

    public func selectAll(_ tasks: [VikunjaTask]) {
        guard isSelecting, !isDeleting else { return }
        selectedIDs = Set(tasks.map(\.id))
    }

    public func reconcile(with tasks: [VikunjaTask]) {
        guard !isDeleting else { return }
        selectedIDs.formIntersection(tasks.map(\.id))
    }

    /// Freeze the visible selection before the first suspension. Successful
    /// deletions are never retried; failures and unattempted items stay selected.
    /// Leaving the list clears the selection even if accepted writes finish later.
    public func delete(
        visibleTasks: [VikunjaTask],
        perform: (VikunjaTask) async -> Bool,
    ) async {
        guard isSelecting, !isDeleting else { return }
        reconcile(with: visibleTasks)
        var seen: Set<EntityID> = []
        let tasks = visibleTasks.filter { selectedIDs.contains($0.id) && seen.insert($0.id).inserted }
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
