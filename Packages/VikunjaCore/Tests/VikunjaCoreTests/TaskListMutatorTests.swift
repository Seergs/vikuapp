import Foundation
import Testing
@testable import VikunjaCore

@Suite("TaskListMutator")
@MainActor
struct TaskListMutatorTests {
    private func makeMutator(
        repository: FakeTaskRepository,
        toast: FakeToastPresenter = FakeToastPresenter(),
        haptics: FakeHapticPresenter = FakeHapticPresenter(),
    ) -> TaskListMutator {
        TaskListMutator(
            repository: repository,
            toastPresenter: toast,
            hapticPresenter: haptics,
            errorMessage: { ($0 as? VikunjaError).map { _ in "friendly" } ?? $0.localizedDescription },
        )
    }

    // MARK: persistToggleDone

    @Test
    func `a completing toggle persists the server copy and plays a success haptic`() async {
        let repository = FakeTaskRepository()
        let haptics = FakeHapticPresenter()
        let mutator = makeMutator(repository: repository, haptics: haptics)
        let original = VikunjaTask(id: 1, title: "A", isDone: false, projectID: 1)
        var flipped = original
        flipped.isDone = true

        let resolved = await mutator.persistToggleDone(flipped: flipped, original: original)

        #expect(resolved.isDone)
        #expect(repository.updatedTasks.map(\.id) == [1])
        #expect(haptics.played == [.success])
    }

    @Test
    func `un-completing a task plays no haptic`() async {
        let haptics = FakeHapticPresenter()
        let mutator = makeMutator(repository: FakeTaskRepository(), haptics: haptics)
        let original = VikunjaTask(id: 1, title: "A", isDone: true, projectID: 1)
        var flipped = original
        flipped.isDone = false

        _ = await mutator.persistToggleDone(flipped: flipped, original: original)

        #expect(haptics.played.isEmpty)
    }

    @Test
    func `a rejected toggle rolls back to the original silently`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)
        let original = VikunjaTask(id: 1, title: "A", isDone: false, projectID: 1)
        var flipped = original
        flipped.isDone = true

        let resolved = await mutator.persistToggleDone(flipped: flipped, original: original)

        #expect(resolved.isDone == false)
        #expect(toast.shown.isEmpty)
    }

    // MARK: persistSetPriority

    @Test
    func `a priority change persists the server copy`() async {
        let repository = FakeTaskRepository()
        let mutator = makeMutator(repository: repository)
        let original = VikunjaTask(id: 1, title: "A", priority: .low, projectID: 1)
        var updated = original
        updated.priority = .high

        let resolved = await mutator.persistSetPriority(updated: updated, original: original)

        #expect(resolved.priority == .high)
        #expect(repository.updatedTasks.map(\.id) == [1])
    }

    @Test
    func `a rejected priority change rolls back to the original silently`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)
        let original = VikunjaTask(id: 1, title: "A", priority: .low, projectID: 1)
        var updated = original
        updated.priority = .high

        let resolved = await mutator.persistSetPriority(updated: updated, original: original)

        #expect(resolved.priority == .low)
        #expect(toast.shown.isEmpty)
    }

    // MARK: persistSetDueDate

    @Test
    func `a due date change persists the server copy`() async {
        let repository = FakeTaskRepository()
        let mutator = makeMutator(repository: repository)
        let original = VikunjaTask(id: 1, title: "A", projectID: 1)
        var updated = original
        updated.dueDate = Date(timeIntervalSince1970: 0)

        let resolved = await mutator.persistSetDueDate(updated: updated, original: original)

        #expect(resolved.dueDate == updated.dueDate)
        #expect(repository.updatedTasks.map(\.id) == [1])
    }

    @Test
    func `a rejected due date change rolls back to the original silently`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)
        let original = VikunjaTask(id: 1, title: "A", projectID: 1)
        var updated = original
        updated.dueDate = Date(timeIntervalSince1970: 0)

        let resolved = await mutator.persistSetDueDate(updated: updated, original: original)

        #expect(resolved.dueDate == nil)
        #expect(toast.shown.isEmpty)
    }

    // MARK: persistToggleLabel

    @Test
    func `adding a label persists it via the label repository`() async {
        let labelRepository = FakeLabelRepository()
        let mutator = makeMutator(repository: FakeTaskRepository())
        let label = Label(id: 5, title: "Work", hexColor: "ff0000")
        let original = VikunjaTask(id: 1, title: "A", projectID: 1)
        var updated = original
        updated.labels.append(label)

        let resolved = await mutator.persistToggleLabel(
            updated: updated, original: original, label: label, isAdding: true, labelRepository: labelRepository,
        )

        #expect(resolved.labels == [label])
        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [5])
    }

    @Test
    func `removing a label persists it via the label repository`() async {
        let labelRepository = FakeLabelRepository()
        let mutator = makeMutator(repository: FakeTaskRepository())
        let label = Label(id: 5, title: "Work", hexColor: "ff0000")
        var original = VikunjaTask(id: 1, title: "A", projectID: 1)
        original.labels = [label]
        let updated = VikunjaTask(id: 1, title: "A", projectID: 1)

        let resolved = await mutator.persistToggleLabel(
            updated: updated, original: original, label: label, isAdding: false, labelRepository: labelRepository,
        )

        #expect(resolved.labels.isEmpty)
        #expect(labelRepository.removedLabelIDs.map(\.labelID) == [5])
    }

    @Test
    func `a rejected label add rolls back to the original silently`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.addError = .network("offline")
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: FakeTaskRepository(), toast: toast)
        let label = Label(id: 5, title: "Work", hexColor: "ff0000")
        let original = VikunjaTask(id: 1, title: "A", projectID: 1)
        var updated = original
        updated.labels.append(label)

        let resolved = await mutator.persistToggleLabel(
            updated: updated, original: original, label: label, isAdding: true, labelRepository: labelRepository,
        )

        #expect(resolved.labels.isEmpty)
        #expect(toast.shown.isEmpty)
    }

    // MARK: delete

    @Test
    func `delete reports removal and shows a success toast`() async {
        let repository = FakeTaskRepository()
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)

        let removed = await mutator.delete(VikunjaTask(id: 7, title: "A", projectID: 1))

        #expect(removed)
        #expect(repository.deletedIDs == [7])
        #expect(toast.shown.last?.style == .success)
    }

    @Test
    func `a failed delete keeps the row and shows an error toast`() async {
        let repository = FakeTaskRepository()
        repository.deleteError = .network("offline")
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)

        let removed = await mutator.delete(VikunjaTask(id: 7, title: "A", projectID: 1))

        #expect(removed == false)
        #expect(toast.shown.last?.style == .error)
    }

    // MARK: move

    @Test
    func `move re-parents the task and shows a success toast`() async {
        let repository = FakeTaskRepository()
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)

        let removed = await mutator.move(
            VikunjaTask(id: 3, title: "A", projectID: 1),
            to: Project(id: 2, title: "Personal"),
        )

        #expect(removed)
        #expect(repository.updatedTasks.first?.projectID == 2)
        #expect(toast.shown.last?.message == "Task moved to Personal")
        #expect(toast.shown.last?.style == .success)
    }

    @Test
    func `a failed move keeps the row and shows an error toast`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let toast = FakeToastPresenter()
        let mutator = makeMutator(repository: repository, toast: toast)

        let removed = await mutator.move(
            VikunjaTask(id: 3, title: "A", projectID: 1),
            to: Project(id: 2, title: "Personal"),
        )

        #expect(removed == false)
        #expect(toast.shown.last?.style == .error)
    }
}
