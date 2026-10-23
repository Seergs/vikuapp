@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct ProjectsListViewModelTests {
    @Test
    func `load builds A tree from parent project ID`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Work", position: 1),
            Project(id: 2, title: "Personal", position: 2),
            Project(id: 3, title: "Work / Client A", parentProjectID: 1, position: 1),
            Project(id: 4, title: "Work / Client B", parentProjectID: 1, position: 2),
            Project(id: 5, title: "Work / Client A / Invoices", parentProjectID: 3, position: 1),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.rootNodes.map(\.project.id) == [1, 2])

        let work = viewModel.rootNodes[0]
        #expect(work.children.map(\.project.id) == [3, 4])
        #expect(work.children[0].children.map(\.project.id) == [5])
        #expect(viewModel.rootNodes[1].children.isEmpty)
    }

    @Test
    func `load separates favorites and saved filters from the real project tree`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Work", position: 1),
            Project(id: -1, title: "Favorites"),
            Project(id: -5, title: "Due this week", position: 2),
            Project(id: -3, title: "Overdue", position: 1),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.rootNodes.map(\.project.id) == [1])
        #expect(viewModel.pseudoNodes.map(\.project.id) == [-1, -3, -5])
    }

    @Test
    func `load orders siblings by position`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Third", position: 3),
            Project(id: 2, title: "First", position: 1),
            Project(id: 3, title: "Second", position: 2),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.rootNodes.map(\.project.title) == ["First", "Second", "Third"])
    }

    @Test
    func `load excludes archived projects`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Active"),
            Project(id: 2, title: "Archived", isArchived: true),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.rootNodes.map(\.project.id) == [1])
    }

    @Test
    func `load drops an archived parents children since they have no attachment point`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Archived parent", isArchived: true),
            Project(id: 2, title: "Orphaned child", parentProjectID: 1),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.rootNodes.isEmpty)
    }

    @Test
    func `load is resilient to A cyclic parent chain`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "A", parentProjectID: 2),
            Project(id: 2, title: "B", parentProjectID: 1),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.rootNodes.isEmpty)
    }

    @Test
    func `load fetches each projects own task summary`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work", position: 1),
            Project(id: 2, title: "Work / Client A", parentProjectID: 1, position: 1),
        ]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [
            VikunjaTask(id: 1, title: "Ship it", isDone: true, projectID: 1),
            VikunjaTask(id: 2, title: "Plan it", isDone: false, projectID: 1),
            VikunjaTask(id: 3, title: "Client task", isDone: false, projectID: 2),
        ]
        let viewModel = ProjectsListViewModel(
            repository: projectRepository,
            taskRepository: taskRepository,
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.taskSummaries[1] == .init(done: 1, total: 2))
        #expect(viewModel.taskSummaries[2] == .init(done: 0, total: 1))
    }

    @Test
    func `shows the cached task summaries before load resolves`() {
        let taskSummaryCache = FakeProjectTaskSummaryCaching(cached: [1: CachedProjectTaskSummary(done: 1, total: 2)])
        let viewModel = ProjectsListViewModel(
            repository: FakeProjectRepository(),
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: taskSummaryCache,
            toastPresenter: FakeToastPresenter(),
        )

        #expect(viewModel.taskSummaries[1] == .init(done: 1, total: 2))
    }

    @Test
    func `load overwrites the cached task summaries once it resolves`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [
            VikunjaTask(id: 1, title: "Ship it", isDone: true, projectID: 1),
            VikunjaTask(id: 2, title: "Plan it", isDone: false, projectID: 1),
        ]
        let taskSummaryCache = FakeProjectTaskSummaryCaching(cached: [1: CachedProjectTaskSummary(done: 0, total: 1)])
        let viewModel = ProjectsListViewModel(
            repository: projectRepository,
            taskRepository: taskRepository,
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: taskSummaryCache,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.taskSummaries[1] == .init(done: 1, total: 2))
        #expect(taskSummaryCache.cached[1] == CachedProjectTaskSummary(done: 1, total: 2))
    }

    @Test
    func `load still succeeds when task summary fetch fails`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.fetchError = .network("offline")
        let viewModel = ProjectsListViewModel(
            repository: projectRepository,
            taskRepository: taskRepository,
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.taskSummaries.isEmpty)
    }

    @Test
    func `load surfaces A friendly message on failure`() async {
        let repository = FakeProjectRepository()
        repository.fetchError = .network("offline")
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
        #expect(viewModel.rootNodes.isEmpty)
    }

    @Test
    func `delete project removes the subtree and shows A success toast`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Work", position: 1),
            Project(id: 2, title: "Personal", position: 2),
            Project(id: 3, title: "Work / Client A", parentProjectID: 1, position: 1),
            Project(id: 4, title: "Work / Client A / Invoices", parentProjectID: 3, position: 1),
        ]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 10, title: "Deep task", projectID: 4)]
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: taskRepository,
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.deleteProject(viewModel.rootNodes[0])

        #expect(viewModel.rootNodes.map(\.project.id) == [2])
        #expect(repository.deletedIDs == [1])
        #expect(viewModel.taskSummaries[4] == nil)
        #expect(toastPresenter.shownMessages.last?.style == .success)
    }

    @Test
    func `delete project removes A nested project without touching its siblings`() async {
        let repository = FakeProjectRepository()
        repository.projects = [
            Project(id: 1, title: "Work", position: 1),
            Project(id: 2, title: "Work / Client A", parentProjectID: 1, position: 1),
            Project(id: 3, title: "Work / Client B", parentProjectID: 1, position: 2),
        ]
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.deleteProject(viewModel.rootNodes[0].children[0])

        #expect(viewModel.rootNodes[0].children.map(\.project.id) == [3])
    }

    @Test
    func `delete project leaves the tree in place and shows an error toast on failure`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: 1, title: "Work")]
        repository.deleteError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.deleteProject(viewModel.rootNodes[0])

        #expect(viewModel.rootNodes.map(\.project.id) == [1])
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }

    @Test
    func `delete project on a saved filter goes through the filter repository with the real filter id`() async {
        let repository = FakeProjectRepository()
        // Project id -6 is the pseudo-project id for saved filter 5
        // (`-id - 1`, see `ProjectKind`).
        repository.projects = [Project(id: -6, title: "Overdue work")]
        let filterRepository = FakeFilterRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: filterRepository,
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.deleteProject(viewModel.pseudoNodes[0])

        #expect(viewModel.pseudoNodes.isEmpty)
        #expect(filterRepository.deletedIDs == [5])
        #expect(repository.deletedIDs.isEmpty)
        #expect(toastPresenter.shownMessages.map(\.message) == ["Filter deleted"])
    }

    @Test
    func `delete project on a saved filter shows an error toast when the filter repository rejects it`() async {
        let repository = FakeProjectRepository()
        repository.projects = [Project(id: -6, title: "Overdue work")]
        let filterRepository = FakeFilterRepository()
        filterRepository.deleteError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectsListViewModel(
            repository: repository,
            taskRepository: FakeTaskRepository(),
            filterRepository: filterRepository,
            taskSummaryCache: FakeProjectTaskSummaryCaching(),
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.deleteProject(viewModel.pseudoNodes[0])

        #expect(viewModel.pseudoNodes.count == 1)
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }
}
