@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddTaskViewModelTests {
    @Test
    func `starts with no project selected and cannot save`() {
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        #expect(viewModel.selectedProjectID == nil)
        #expect(viewModel.canSave == false)
    }

    @Test
    func `load populates non archived projects sorted by position`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Later", isArchived: false, position: 2),
            Project(id: 2, title: "Archived", isArchived: true, position: 0),
            Project(id: 3, title: "First", isArchived: false, position: 1),
        ]
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.projects.map(\.id) == [3, 1])
    }

    @Test
    func `load surfaces A friendly message on failure`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.fetchError = .network("offline")
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
    }

    @Test
    func `can save requires both A title and A project`() {
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        viewModel.title = "   "
        viewModel.selectedProjectID = 1
        #expect(viewModel.canSave == false)

        viewModel.title = "Buy milk"
        viewModel.selectedProjectID = nil
        #expect(viewModel.canSave == false)

        viewModel.selectedProjectID = 1
        #expect(viewModel.canSave == true)
    }

    @Test
    func `save creates A task with the chosen project and priority`() async {
        let taskRepository = FakeTaskRepository()
        let viewModel = QuickAddTaskViewModel(
            taskRepository: taskRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        viewModel.title = "  Buy milk  "
        viewModel.selectedProjectID = 7
        viewModel.priority = .high

        let created = await viewModel.save()

        #expect(created?.title == "Buy milk")
        #expect(created?.projectID == 7)
        #expect(created?.priority == .high)
        #expect(viewModel.isSaving == false)
        #expect(viewModel.saveErrorMessage == nil)
    }

    @Test
    func `save shows A success toast`() async {
        let taskRepository = FakeTaskRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = QuickAddTaskViewModel(
            taskRepository: taskRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )
        viewModel.title = "Buy milk"
        viewModel.selectedProjectID = 7

        _ = await viewModel.save()

        #expect(toastPresenter.shownMessages.count == 1)
        #expect(toastPresenter.shownMessages.first?.message == "Task created")
        #expect(toastPresenter.shownMessages.first?.style == .success)
    }

    @Test
    func `save broadcasts the created task's project`() async {
        let broadcaster = FakeTaskChangeBroadcaster()
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            taskChangeBroadcaster: broadcaster,
        )
        viewModel.title = "Buy milk"
        viewModel.selectedProjectID = 7

        _ = await viewModel.save()

        #expect(broadcaster.lastCreatedTask?.projectID == 7)
    }

    @Test
    func `save does nothing when the form is incomplete`() async {
        let taskRepository = FakeTaskRepository()
        let viewModel = QuickAddTaskViewModel(
            taskRepository: taskRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        viewModel.title = "Buy milk"

        let created = await viewModel.save()

        #expect(created == nil)
    }

    @Test
    func `load exposes the non-archived projects ordered by position`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work", parentProjectID: nil, position: 0),
            Project(id: 2, title: "Redesign", parentProjectID: 1, position: 1),
            Project(id: 3, title: "Archived", isArchived: true, parentProjectID: nil, position: 2),
            Project(id: 4, title: "Launch", parentProjectID: 1, position: 0),
        ]
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.projects.map(\.id) == [1, 4, 2])
    }

    @Test
    func `selected project resolves the chosen ID against the loaded projects`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        #expect(viewModel.selectedProject == nil)

        viewModel.selectedProjectID = 1

        #expect(viewModel.selectedProject?.title == "Work")
    }

    @Test
    func `save surfaces A friendly message on failure`() async {
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FailingTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        viewModel.title = "Buy milk"
        viewModel.selectedProjectID = 1

        let created = await viewModel.save()

        #expect(created == nil)
        #expect(viewModel.saveErrorMessage == "Couldn't reach that server. Check the address and your connection.")
    }

    @Test
    func `starts on the preselected project when opened from A project screen`() {
        let viewModel = QuickAddTaskViewModel(
            preselectedProjectID: 5,
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        #expect(viewModel.selectedProjectID == 5)
    }

    @Test
    func `load falls back to the account default project when nothing was preselected`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work"), Project(id: 3, title: "Inbox")]
        let viewModel = QuickAddTaskViewModel(
            accountDefaultProjectID: 3,
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.selectedProjectID == 3)
    }

    @Test
    func `load ignores A default project that is not among the loaded projects`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let viewModel = QuickAddTaskViewModel(
            accountDefaultProjectID: 99,
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.selectedProjectID == nil)
    }

    @Test
    func `load keeps an explicit preselection over the account default`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 5, title: "Work"), Project(id: 3, title: "Inbox")]
        let viewModel = QuickAddTaskViewModel(
            preselectedProjectID: 5,
            accountDefaultProjectID: 3,
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.selectedProjectID == 5)
    }
}

private final class FailingTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    func fetchTasks(projectID _: Int) async throws -> [VikunjaTask] {
        []
    }

    func fetchTask(id _: Int) async throws -> VikunjaTask {
        throw VikunjaError.notFound
    }

    func create(_: VikunjaTask) async throws -> VikunjaTask {
        throw VikunjaError.network("offline")
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func delete(id _: Int) async throws {}
    func searchTasks(query _: String) async throws -> [VikunjaTask] {
        []
    }
}
