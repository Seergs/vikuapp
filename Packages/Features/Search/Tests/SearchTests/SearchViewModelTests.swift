@testable import Search
import Testing
import VikunjaCore

@MainActor
struct SearchViewModelTests {
    private func makeViewModel(
        tasks: [VikunjaTask],
        taskRepository: FakeTaskRepository = FakeTaskRepository(),
        toast: FakeToastPresenter = FakeToastPresenter(),
        haptics: FakeHapticPresenter = FakeHapticPresenter(),
    ) -> SearchViewModel {
        taskRepository.tasks = tasks
        let viewModel = SearchViewModel(
            taskRepository: taskRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toast,
            hapticPresenter: haptics,
        )
        viewModel.state = .loaded(tasks)
        return viewModel
    }

    @Test
    func `toggling a task to done flips it optimistically and plays a success haptic`() async throws {
        let haptics = FakeHapticPresenter()
        let viewModel = makeViewModel(
            tasks: [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)],
            haptics: haptics,
        )

        try await viewModel.toggleDone(#require(viewModel.state.value?[0]))

        #expect(viewModel.state.value?[0].isDone == true)
        #expect(haptics.played == [.success])
    }

    @Test
    func `a rejected toggle rolls back`() async throws {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let viewModel = makeViewModel(
            tasks: [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)],
            taskRepository: repository,
        )

        try await viewModel.toggleDone(#require(viewModel.state.value?[0]))

        #expect(viewModel.state.value?[0].isDone == false)
    }

    @Test
    func `delete removes the task and shows a success toast`() async throws {
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(
            tasks: [
                VikunjaTask(id: 1, title: "Write report", projectID: 1),
                VikunjaTask(id: 2, title: "Review PR", projectID: 1),
            ],
            toast: toast,
        )

        try await viewModel.delete(#require(viewModel.state.value?[0]))

        #expect(viewModel.state.value?.map(\.id) == [2])
        #expect(toast.shown.last?.style == .success)
    }

    @Test
    func `a failed delete leaves the task in place and shows an error toast`() async throws {
        let repository = FakeTaskRepository()
        repository.deleteError = .network("offline")
        let toast = FakeToastPresenter()
        let viewModel = makeViewModel(
            tasks: [VikunjaTask(id: 1, title: "Write report", projectID: 1)],
            taskRepository: repository,
            toast: toast,
        )

        try await viewModel.delete(#require(viewModel.state.value?[0]))

        #expect(viewModel.state.value?.map(\.id) == [1])
        #expect(toast.shown.last?.style == .error)
    }
}
