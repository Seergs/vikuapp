@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct ProjectOverviewViewModelTests {
    @Test
    func `mark visible claims the quick add context and mark hidden releases it`() {
        let context = FakeQuickAddContext()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 7, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
            quickAddContext: context,
        )

        viewModel.markVisible()
        #expect(context.preselectedProjectID == 7)

        viewModel.markHidden()
        #expect(context.preselectedProjectID == nil)
    }

    @Test
    func `mark hidden leaves an outer project scope selected`() {
        let context = FakeQuickAddContext()
        context.enterProjectScope(99)
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 7, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
            quickAddContext: context,
        )

        viewModel.markVisible()
        #expect(context.preselectedProjectID == 7)

        viewModel.markHidden()
        #expect(context.preselectedProjectID == 99)
    }

    @Test
    func `last created task for this project reflects only A matching broadcast`() {
        let broadcaster = FakeTaskChangeBroadcaster()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 7, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
            taskChangeBroadcaster: broadcaster,
        )

        broadcaster.taskCreated(projectID: 99)
        #expect(viewModel.lastCreatedTaskForThisProject == nil)

        broadcaster.taskCreated(projectID: 7)
        #expect(viewModel.lastCreatedTaskForThisProject?.projectID == 7)
    }

    @Test
    func `load fetches the projects tasks`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Review PR", projectID: 1),
            VikunjaTask(id: 3, title: "Other project's task", projectID: 2),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.tasks.map(\.id) == [1, 2])
    }

    @Test
    func `load surfaces A friendly message on failure`() async {
        let repository = FakeTaskRepository()
        repository.fetchError = .network("offline")
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
        #expect(viewModel.tasks.isEmpty)
    }

    @Test
    func `load carries the subprojects handed in at construction`() {
        let repository = FakeTaskRepository()
        let subprojects = [ProjectNode(project: Project(id: 2, title: "Client A", parentProjectID: 1))]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            subprojects: subprojects,
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        #expect(viewModel.subprojects.map(\.project.id) == [2])
    }

    @Test
    func `load fetches each subprojects own task summary`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Parent task", projectID: 1),
            VikunjaTask(id: 2, title: "Client A task 1", isDone: true, projectID: 2),
            VikunjaTask(id: 3, title: "Client A task 2", isDone: false, projectID: 2),
            VikunjaTask(id: 4, title: "Client B task", isDone: false, projectID: 3),
        ]
        let subprojects = [
            ProjectNode(project: Project(id: 2, title: "Client A", parentProjectID: 1)),
            ProjectNode(project: Project(id: 3, title: "Client B", parentProjectID: 1)),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            subprojects: subprojects,
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.subprojectTaskSummaries[2] == .init(done: 1, total: 2))
        #expect(viewModel.subprojectTaskSummaries[3] == .init(done: 0, total: 1))
    }

    @Test
    func `load omits A subproject summary when its fetch fails`() async {
        let repository = FakeTaskRepository()
        repository.fetchError = .network("offline")
        let subprojects = [ProjectNode(project: Project(id: 2, title: "Client A", parentProjectID: 1))]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            subprojects: subprojects,
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        // The main project's own fetch fails first (surfacing the load
        // error), so subproject summaries never even get requested here —
        // this just confirms a failed fetch doesn't crash or leave a
        // stale/partial summary.
        #expect(viewModel.subprojectTaskSummaries.isEmpty)
    }

    @Test
    func `toggle done persists the flipped state through the repository`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == true)
    }

    @Test
    func `toggle done reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        repository.updateError = .network("offline")

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == false)
    }

    @Test
    func `completing a task plays a success haptic but un-completing does not`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1)]
        let haptics = FakeHapticPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            hapticPresenter: haptics,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.toggleDone(viewModel.tasks[0])
        #expect(haptics.played == [.success])

        await viewModel.toggleDone(viewModel.tasks[0])
        #expect(haptics.played == [.success])
    }

    @Test
    func `delete removes the task and shows A success toast`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Review PR", projectID: 1),
        ]
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.delete(viewModel.tasks[0])

        #expect(viewModel.tasks.map(\.id) == [2])
        #expect(toastPresenter.shownMessages.last?.style == .success)
    }

    @Test
    func `delete leaves the task in place and shows an error toast on failure`() async {
        let repository = FakeTaskRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 1)
        repository.tasks = [task]
        repository.deleteError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.delete(task)

        #expect(viewModel.tasks.map(\.id) == [1])
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }

    @Test
    func `move updates the tasks project and removes it from the local list`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Review PR", projectID: 1),
        ]
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let destination = Project(id: 2, title: "Personal")

        await viewModel.move(viewModel.tasks[0], to: destination)

        #expect(viewModel.tasks.map(\.id) == [2])
        #expect(repository.tasks.first { $0.id == 1 }?.projectID == 2)
        #expect(toastPresenter.shownMessages.last?.style == .success)
    }

    @Test
    func `move leaves the task in place and shows an error toast on failure`() async {
        let repository = FakeTaskRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 1)
        repository.tasks = [task]
        repository.updateError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.move(task, to: Project(id: 2, title: "Personal"))

        #expect(viewModel.tasks.map(\.id) == [1])
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }

    @Test
    func `loadMoveCandidates populates the move-picker projects`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Personal"),
            Project(id: 3, title: "Client A", parentProjectID: 2),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.loadMoveCandidates()

        #expect(viewModel.allProjects.map(\.id) == [1, 2, 3])
    }
}
