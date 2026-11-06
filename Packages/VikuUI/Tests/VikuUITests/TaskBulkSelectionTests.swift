import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

@MainActor
struct TaskBulkSelectionTests {
    private let tasks = [
        VikunjaTask(id: 1, title: "First", projectID: 1),
        VikunjaTask(id: 2, title: "Second", projectID: 1),
        VikunjaTask(id: 3, title: "Hidden", projectID: 1),
    ]

    @Test func `select all replaces selection with only the displayed tasks`() {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.toggle(3)
        #expect(selection.selectedIDs.isEmpty)
        selection.begin()
        selection.toggle(3)
        selection.selectAll(Array(tasks.prefix(2)))
        #expect(selection.selectedIDs == [1, 2])
        selection.toggle(1)
        #expect(selection.selectedIDs == [2])
        selection.reset()
        #expect(selection.selectedIDs.isEmpty)
        #expect(!selection.isSelecting)
    }

    @Test func `selection removes tasks which leave the list`() {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        selection.reconcile(with: [tasks[1]])
        #expect(selection.selectedIDs == [2])
    }

    @Test func `delete excludes hidden tasks and deduplicates visible tasks`() async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        selection.begin()
        selection.selectAll(tasks)
        var deleted: [EntityID] = []
        await selection.delete(visibleTasks: [tasks[0], tasks[0], tasks[1]]) { task in
            deleted.append(task.id)
            return true
        }
        #expect(deleted == [1, 2])
        #expect(selection.selectedIDs.isEmpty)
        #expect(!selection.isSelecting)
        #expect(!selection.isDeleting)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.last?.style == .success)
    }

    @Test func `partial failure retains only failed tasks and retry does not repeat successes`() async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        selection.begin()
        selection.selectAll(tasks)
        await selection.delete(visibleTasks: tasks) { $0.id != 2 }
        #expect(selection.selectedIDs == [2])
        #expect(selection.isSelecting)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.last?.style == .error)
        var retried: [EntityID] = []
        await selection.delete(visibleTasks: tasks) { task in
            retried.append(task.id)
            return true
        }
        #expect(retried == [2])
        #expect(!selection.isSelecting)
    }

    @Test func `total failure keeps selection recoverable`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        await selection.delete(visibleTasks: tasks) { _ in false }
        #expect(selection.selectedIDs == [1, 2, 3])
        #expect(selection.isSelecting)
        #expect(!selection.isDeleting)
    }

    @Test func `empty or inactive deletion does not issue writes or feedback`() async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        await selection.delete(visibleTasks: tasks) { _ in
            Issue.record("inactive selection must not delete")
            return true
        }
        selection.begin()
        await selection.delete(visibleTasks: tasks) { _ in
            Issue.record("empty selection must not delete")
            return true
        }
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `slow deletion freezes selection and rejects duplicate submissions`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        var deleted: [EntityID] = []
        await selection.delete(visibleTasks: tasks) { task in
            #expect(selection.isDeleting)
            selection.toggle(3)
            selection.selectAll([])
            selection.begin()
            selection.reconcile(with: [])
            await selection.delete(visibleTasks: tasks) { _ in
                Issue.record("duplicate submission must not delete")
                return true
            }
            await Task.yield()
            deleted.append(task.id)
            return true
        }
        #expect(deleted == [1, 2, 3])
    }

    @Test func `leaving during deletion never restores failed selection`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        var attempted: [EntityID] = []
        await selection.delete(visibleTasks: tasks) { task in
            selection.reset()
            await Task.yield()
            attempted.append(task.id)
            return false
        }
        #expect(attempted == [1, 2, 3])
        #expect(selection.selectedIDs.isEmpty)
        #expect(!selection.isSelecting)
    }

    @Test func `cancellation keeps unattempted tasks selected`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        let operation = Task {
            await selection.delete(visibleTasks: tasks) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }
        }
        await operation.value
        #expect(selection.selectedIDs == [2, 3])
        #expect(selection.isSelecting)
        #expect(!selection.isDeleting)
    }
}

@MainActor
struct TaskBulkCompletionSelectionTests {
    private var tasks: [VikunjaTask] {
        [
            VikunjaTask(id: 1, title: "Pending", projectID: 1),
            VikunjaTask(id: 2, title: "Completed", isDone: true, projectID: 1),
            VikunjaTask(id: 3, title: "Hidden", projectID: 1),
        ]
    }

    @Test func `homogeneous selections offer one target while mixed selections require a choice`() {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.toggle(1)
        #expect(selection.completionTarget(visibleTasks: tasks) == true)
        selection.toggle(2)
        #expect(selection.completionTarget(visibleTasks: tasks) == nil)
        selection.toggle(1)
        #expect(selection.completionTarget(visibleTasks: tasks) == false)
    }

    @Test(arguments: [true, false])
    func `completion applies one explicit state to the entire visible selection`(isDone: Bool) async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        selection.begin()
        selection.selectAll(tasks)
        var submitted: [EntityID] = []
        await selection.setCompletion(visibleTasks: [tasks[0], tasks[1], tasks[0]], isDone: isDone) { changes in
            submitted = changes.map(\.id)
        }
        #expect(submitted == [1, 2])
        #expect(!selection.isSelecting)
        #expect(!selection.isPerformingAction)
        #expect(selection.selectedIDs.isEmpty)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.first?.style == .success)
    }

    @Test func `failed local acceptance keeps the whole selection available to retry`() async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        selection.begin()
        selection.selectAll(tasks)
        await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in
            throw VikunjaError.notFound
        }
        #expect(selection.selectedIDs == [1, 2, 3])
        #expect(selection.isSelecting)
        #expect(!selection.isPerformingAction)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.first?.style == .error)
        await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in }
        #expect(!selection.isSelecting)
    }

    @Test func `cancellation preserves selection without a failure toast`() async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        selection.begin()
        selection.selectAll(tasks)
        await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in throw CancellationError() }
        #expect(selection.selectedIDs == [1, 2, 3])
        #expect(!selection.isPerformingAction)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `an empty selection never submits a write`() async {
        let toast = FakeToastPresenter()
        let selection = TaskBulkSelection(toastPresenter: toast)
        selection.begin()
        await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in Issue.record("Empty write") }
        #expect(selection.isSelecting)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `slow completion blocks duplicate writes deletion and selection changes`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in
            #expect(selection.isUpdatingCompletion)
            #expect(selection.isPerformingAction)
            #expect(!selection.isDeleting)
            selection.begin()
            selection.toggle(1)
            selection.selectAll([])
            selection.reconcile(with: [])
            #expect(selection.selectedIDs == [1, 2, 3])
            await selection.setCompletion(visibleTasks: tasks, isDone: false) { _ in
                Issue.record("Duplicate completion")
            }
            await selection.delete(visibleTasks: tasks) { _ in
                Issue.record("Deletion during completion")
                return true
            }
            await Task.yield()
        }
        #expect(!selection.isPerformingAction)
    }

    @Test func `deletion also blocks a simultaneous completion`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        await selection.delete(visibleTasks: tasks) { _ in
            await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in
                Issue.record("Completion during deletion")
            }
            return true
        }
    }

    @Test func `leaving during a failed completion never restores selection`() async {
        let selection = TaskBulkSelection(toastPresenter: FakeToastPresenter())
        selection.begin()
        selection.selectAll(tasks)
        await selection.setCompletion(visibleTasks: tasks, isDone: true) { _ in
            selection.reset()
            await Task.yield()
            throw VikunjaError.notFound
        }
        #expect(selection.selectedIDs.isEmpty)
        #expect(!selection.isSelecting)
        #expect(!selection.isPerformingAction)
    }
}
