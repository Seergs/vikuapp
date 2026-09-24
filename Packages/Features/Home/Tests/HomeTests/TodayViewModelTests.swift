@testable import Home
import Testing
import VikunjaCore

@MainActor
struct TodayViewModelTests {
    @Test
    func `load merges tasks across every project`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Personal"),
        ]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Buy groceries", projectID: 2),
        ]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(Set(viewModel.tasks.map(\.id)) == [1, 2])
        #expect(viewModel.projectsByID[1]?.title == "Work")
        #expect(viewModel.projectsByID[2]?.title == "Personal")
    }

    @Test
    func `load drops A task list whose project fetch fails`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Personal"),
        ]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Buy groceries", projectID: 2),
        ]
        taskRepository.failingProjectIDs = [2]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.tasks.map(\.id) == [1])
    }

    @Test
    func `load surfaces A friendly message when fetching projects fails`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.fetchError = .network("offline")
        let viewModel = TodayViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
        #expect(viewModel.tasks.isEmpty)
    }

    @Test
    func `toggle done persists the flipped state through the repository`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == true)
    }

    @Test
    func `toggle done reverts when the server rejects the update`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        taskRepository.updateError = .network("offline")

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == false)
    }

    @Test
    func `set priority persists the new priority through the repository`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", priority: .low, projectID: 1)]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.setPriority(viewModel.tasks[0], to: .urgent)

        #expect(viewModel.tasks[0].priority == .urgent)
    }

    @Test
    func `set priority reverts when the server rejects the update`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", priority: .low, projectID: 1)]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        taskRepository.updateError = .network("offline")

        await viewModel.setPriority(viewModel.tasks[0], to: .urgent)

        #expect(viewModel.tasks[0].priority == .low)
    }

    @Test
    func `completing a task plays a success haptic but un-completing does not`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)]
        let haptics = FakeHapticPresenter()
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            hapticPresenter: haptics,
        )
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])
        #expect(haptics.played == [.success])

        await viewModel.toggleDone(viewModel.tasks[0])
        #expect(haptics.played == [.success])
    }
}
