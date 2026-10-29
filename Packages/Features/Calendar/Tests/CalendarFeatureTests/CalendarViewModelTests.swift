@testable import CalendarFeature
import Foundation
import Testing
import VikunjaCore

@MainActor
struct CalendarViewModelTests {
    private func makeViewModel(
        projects: [Project] = [Project(id: 1, title: "Work")],
        tasks: [VikunjaTask] = [],
        failingProjectIDs: Set<Int> = [],
        projectFetchError: VikunjaError? = nil,
        updateError: VikunjaError? = nil,
        haptics: FakeHapticPresenter = FakeHapticPresenter(),
    ) -> CalendarViewModel {
        let projectRepo = FakeProjectRepository()
        projectRepo.projects = projects
        projectRepo.fetchError = projectFetchError
        let taskRepo = FakeTaskRepository()
        taskRepo.tasks = tasks
        taskRepo.failingProjectIDs = failingProjectIDs
        taskRepo.updateError = updateError
        return CalendarViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            hapticPresenter: haptics,
        )
    }

    private func dated(_ id: Int, project: Int = 1, done: Bool = false) -> VikunjaTask {
        VikunjaTask(id: .remote(id), title: "Task \(id)", isDone: done, dueDate: Date(), projectID: .remote(project))
    }

    @Test
    func `load merges every project's tasks and indexes projects`() async {
        let viewModel = makeViewModel(
            projects: [Project(id: 1, title: "Work"), Project(id: 2, title: "Home")],
            tasks: [dated(1, project: 1), dated(2, project: 2)],
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(Set(viewModel.tasks.map(\.id)) == [1, 2])
        #expect(viewModel.projectsByID[2]?.title == "Home")
    }

    @Test
    func `a failing project is dropped, not fatal`() async {
        let viewModel = makeViewModel(
            projects: [Project(id: 1, title: "Work"), Project(id: 2, title: "Home")],
            tasks: [dated(1, project: 1), dated(2, project: 2)],
            failingProjectIDs: [2],
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.tasks.map(\.id) == [1])
    }

    @Test
    func `a project fetch failure surfaces as a failure state`() async {
        let viewModel = makeViewModel(projectFetchError: .network("offline"))

        await viewModel.load()

        guard case .failure = viewModel.loadState else {
            Issue.record("expected failure, got \(viewModel.loadState)")
            return
        }
    }

    @Test
    func `toggling a task to done plays a success haptic`() async {
        let haptics = FakeHapticPresenter()
        let viewModel = makeViewModel(tasks: [dated(1)], haptics: haptics)
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone)
        #expect(haptics.played == [.success])
    }

    @Test
    func `a rejected toggle rolls back`() async {
        let viewModel = makeViewModel(tasks: [dated(1)], updateError: .network("offline"))
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == false)
    }

    @Test
    func `un-completing a task plays no haptic`() async {
        let haptics = FakeHapticPresenter()
        let viewModel = makeViewModel(tasks: [dated(1, done: true)], haptics: haptics)
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == false)
        #expect(haptics.played.isEmpty)
    }
}
