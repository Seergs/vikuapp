import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct ProjectOverviewViewModelTests {
    @Test
    func `load leaves supports kanban false when the capability provider reports no api v2`() async {
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.supportsKanban == false)
    }

    @Test
    func `load sets supports kanban true when the capability provider reports api v2`() async {
        let capabilityProvider = FakeCapabilityProvider()
        capabilityProvider.supportedFeatures = [.apiV2]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            capabilityProvider: capabilityProvider,
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.supportsKanban == true)
    }

    @Test
    func `load succeeds for a project created offline that has not synced yet`() async {
        // Regression test: a `.local` project (offline-created, never
        // synced) used to fail the whole load with "not found" - there was
        // nothing wrong with the project itself, `fetchTasks(projectID:)`
        // simply had no way to represent a local-only project before it
        // widened from `Int` to `EntityID`.
        let localProjectID = EntityID.local(UUID())
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: .local(UUID()), title: "Buy milk", projectID: localProjectID)]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: localProjectID, title: "Errands"),
            repository: taskRepository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.tasks.map(\.title) == ["Buy milk"])
    }

    @Test
    func `load leaves supports kanban false for favorites even when the server supports api v2`() async {
        // Favorites (id -1) is a pseudo-project with no row in the real
        // `projects` table, so the server has no /views entries for it -
        // the List/Kanban switcher must stay hidden regardless of server
        // capability.
        let capabilityProvider = FakeCapabilityProvider()
        capabilityProvider.supportedFeatures = [.apiV2]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: -1, title: "Favorites"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            capabilityProvider: capabilityProvider,
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.supportsKanban == false)
    }

    @Test
    func `load keeps supports kanban true for A saved filter when the server supports api v2`() async {
        // Saved filters (negative ids other than -1) are real server-side
        // resources and do have their own /views, unlike Favorites - only
        // Favorites should lose the switcher.
        let capabilityProvider = FakeCapabilityProvider()
        capabilityProvider.supportedFeatures = [.apiV2]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: -2, title: "Overdue"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            capabilityProvider: capabilityProvider,
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.supportsKanban == true)
    }

    @Test
    func `mark visible claims the quick add context and mark hidden releases it`() {
        let context = FakeQuickAddContext()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 7, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
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
        context.enterProjectScope(Project(id: 99, title: "Outer"))
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 7, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        #expect(viewModel.subprojects.map(\.project.id) == [2])
    }

    @Test
    func `load refreshes the projects own title and color from the server`() async {
        // Regression test: this view model is cached indefinitely per
        // project id (`ProjectsRootView`), so renaming a project or
        // changing its color from the edit sheet must still show up on this
        // screen on a revisit, not just in the projects list.
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Renamed", hexColor: "00ff00")]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work", hexColor: "ff0000"),
            repository: FakeTaskRepository(),
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.project.title == "Renamed")
        #expect(viewModel.project.hexColor == "00ff00")
    }

    @Test
    func `load replaces the construction-time subprojects snapshot with a fresh fetch`() async {
        // Regression test: this view model is cached indefinitely per
        // project id (`ProjectsRootView`), so a subproject created or
        // deleted elsewhere after this instance was first built (e.g. from
        // the root Projects list) must still show up correctly next time
        // `load()` runs, not just whatever was handed in at construction.
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Client A", parentProjectID: 1),
            Project(id: 3, title: "Client C", parentProjectID: 1),
        ]
        let staleSubprojects = [ProjectNode(project: Project(id: 2, title: "Client A", parentProjectID: 1))]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            subprojects: staleSubprojects,
            repository: FakeTaskRepository(),
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.subprojects.map(\.project.id) == [2, 3])
    }

    @Test
    func `add subproject appends it to the local tree and seeds its summary at zero`() {
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        viewModel.addSubproject(Project(id: 2, title: "Client A", parentProjectID: 1))

        #expect(viewModel.subprojects.map(\.project.id) == [2])
        #expect(viewModel.subprojectTaskSummaries[2] == ProjectOverviewViewModel.TaskSummary(done: 0, total: 0))
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
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Client A", parentProjectID: 1),
            Project(id: 3, title: "Client B", parentProjectID: 1),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.subprojectTaskSummaries[2] == .init(done: 1, total: 2))
        #expect(viewModel.subprojectTaskSummaries[3] == .init(done: 0, total: 1))
    }

    @Test
    func `subprojects with pending tasks excludes completed and empty subprojects`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Client A task", isDone: false, projectID: 2),
            VikunjaTask(id: 2, title: "Client B task", isDone: true, projectID: 3),
        ]
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Client A", parentProjectID: 1),
            Project(id: 3, title: "Client B", parentProjectID: 1),
            Project(id: 4, title: "Client C", parentProjectID: 1),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        // Client A (2) has an open task, Client B (3) is fully done, Client C
        // (4) has none at all — only Client A has anything pending.
        #expect(viewModel.subprojects.map(\.project.id) == [2, 3, 4])
        #expect(viewModel.subprojectsWithPendingTasks.map(\.project.id) == [2])
    }

    @Test
    func `subprojects with pending tasks keeps A subproject whose summary fetch failed`() async {
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
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.subprojectTaskSummaries[2] == nil)
        #expect(viewModel.subprojectsWithPendingTasks.map(\.project.id) == [2])
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        repository.updateError = .network("offline")

        await viewModel.toggleDone(viewModel.tasks[0])

        #expect(viewModel.tasks[0].isDone == false)
    }

    @Test
    func `set priority persists the new priority through the repository`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", priority: .low, projectID: 1)]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.setPriority(viewModel.tasks[0], to: .urgent)

        #expect(viewModel.tasks[0].priority == .urgent)
    }

    @Test
    func `set priority reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", priority: .low, projectID: 1)]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        repository.updateError = .network("offline")

        await viewModel.setPriority(viewModel.tasks[0], to: .urgent)

        #expect(viewModel.tasks[0].priority == .low)
    }

    @Test
    func `set due date persists the new due date through the repository`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let newDate = Date(timeIntervalSince1970: 0)

        await viewModel.setDueDate(viewModel.tasks[0], to: newDate)

        #expect(viewModel.tasks[0].dueDate == newDate)
    }

    @Test
    func `set due date reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        let original = VikunjaTask(id: 1, title: "Write report", dueDate: Date(timeIntervalSince1970: 0), projectID: 1)
        repository.tasks = [original]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        repository.updateError = .network("offline")

        await viewModel.setDueDate(viewModel.tasks[0], to: nil)

        #expect(viewModel.tasks[0].dueDate == original.dueDate)
    }

    @Test
    func `toggle label adds A label through the label repository`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let labelRepository = FakeLabelRepository()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let label = Label(id: 5, title: "Urgent", hexColor: "ff0000")

        await viewModel.toggleLabel(viewModel.tasks[0], label)

        #expect(viewModel.tasks[0].labels == [label])
        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [5])
    }

    @Test
    func `toggle label removes an already attached label`() async {
        let repository = FakeTaskRepository()
        let label = Label(id: 5, title: "Urgent", hexColor: "ff0000")
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1, labels: [label])]
        let labelRepository = FakeLabelRepository()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.toggleLabel(viewModel.tasks[0], label)

        #expect(viewModel.tasks[0].labels.isEmpty)
        #expect(labelRepository.removedLabelIDs.map(\.labelID) == [5])
    }

    @Test
    func `toggle label reverts when the server rejects it`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let labelRepository = FakeLabelRepository()
        labelRepository.addError = .network("offline")
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let label = Label(id: 5, title: "Urgent", hexColor: "ff0000")

        await viewModel.toggleLabel(viewModel.tasks[0], label)

        #expect(viewModel.tasks[0].labels.isEmpty)
    }

    @Test
    func `create and add label creates then attaches the new label`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let labelRepository = FakeLabelRepository()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.createAndAddLabel(viewModel.tasks[0], title: "Urgent", hexColor: "ff0000")

        #expect(viewModel.allLabels.map(\.title) == ["Urgent"])
        #expect(viewModel.tasks[0].labels.map(\.title) == ["Urgent"])
        #expect(labelRepository.addedLabelIDs.count == 1)
    }

    @Test
    func `add relation persists through the relation repository and shows A success toast`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let relationRepository = FakeTaskRelationRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            filterRepository: FakeFilterRepository(),
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let candidate = TaskRelation(id: 9, title: "Draft appendix", projectID: 1)

        await viewModel.addRelation(candidate, kind: .related, to: viewModel.tasks[0])

        #expect(relationRepository.addedRelations.map(\.kind) == [.related])
        #expect(relationRepository.addedRelations.map(\.otherTaskID) == [9])
        #expect(relationRepository.addedRelations.map(\.taskID) == [1])
        #expect(toastPresenter.shownMessages.map(\.message) == ["Relation added"])
    }

    @Test
    func `add relation shows an error toast when the server rejects it`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let relationRepository = FakeTaskRelationRepository()
        relationRepository.addError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            filterRepository: FakeFilterRepository(),
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()

        await viewModel.addRelation(
            TaskRelation(id: 9, title: "Draft appendix", projectID: 1), kind: .related, to: viewModel.tasks[0],
        )

        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `search tasks for relation excludes the task itself and already related tasks`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(
                id: 1, title: "Write report", projectID: 1,
                dependsOn: [TaskRelation(id: 3, title: "Approve brief", projectID: 1)],
            ),
            VikunjaTask(id: 3, title: "Approve brief", projectID: 1),
            VikunjaTask(id: 9, title: "Draft appendix", projectID: 1),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let task = viewModel.tasks[0]

        await viewModel.searchTasksForRelation(for: task, query: "a")

        #expect(viewModel.relationSearchResults.map(\.id) == [9])
    }

    @Test
    func `load relation suggestions populates from the tasks own project excluding self`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Outline", projectID: 1),
        ]
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await viewModel.load()
        let task = viewModel.tasks[0]

        await viewModel.loadRelationSuggestions(for: task)

        #expect(viewModel.relationSearchResults.map(\.id) == [2])
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
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
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.loadMoveCandidates()

        #expect(viewModel.allProjects.map(\.id) == [1, 2, 3])
    }

    @Test
    func `delete project on a real project goes through the project repository, not the filter repository`() async {
        let projectRepository = FakeProjectRepository()
        let filterRepository = FakeFilterRepository()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: filterRepository,
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        let result = await viewModel.deleteProject()

        #expect(result == true)
        #expect(projectRepository.deletedIDs == [1])
        #expect(filterRepository.deletedIDs.isEmpty)
    }

    @Test
    func `delete project on a saved filter goes through the filter repository with the real filter id`() async {
        // Project id -6 is the pseudo-project id for saved filter 5
        // (`-id - 1`, see `ProjectKind`).
        let projectRepository = FakeProjectRepository()
        let filterRepository = FakeFilterRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: -6, title: "Overdue work"),
            repository: FakeTaskRepository(),
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: filterRepository,
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )

        let result = await viewModel.deleteProject()

        #expect(result == true)
        #expect(filterRepository.deletedIDs == [5])
        #expect(projectRepository.deletedIDs.isEmpty)
        #expect(toastPresenter.shownMessages.map(\.message) == ["Filter deleted"])
    }

    @Test
    func `delete project on a saved filter shows an error toast when the filter repository rejects it`() async {
        let filterRepository = FakeFilterRepository()
        filterRepository.deleteError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: -6, title: "Overdue work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: filterRepository,
            toastPresenter: toastPresenter,
            taskSortStore: FakeTaskSortStore(),
        )

        let result = await viewModel.deleteProject()

        #expect(result == false)
        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `load populates saved filter query from the filter repository`() async {
        // Project id -6 is the pseudo-project id for saved filter 5
        // (`-id - 1`, see `ProjectKind`).
        let filterRepository = FakeFilterRepository()
        filterRepository.filter = SavedFilterDetail(
            id: 5,
            title: "Overdue work",
            description: "",
            isFavorite: false,
            query: "priority >= 3 && done = false",
        )
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: -6, title: "Overdue work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: filterRepository,
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.savedFilterQuery == "priority >= 3 && done = false")
    }

    @Test
    func `load leaves saved filter query nil for a real project`() async {
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.savedFilterQuery == nil)
    }

    @Test
    func `load leaves saved filter query nil when the filter repository fetch fails`() async {
        let filterRepository = FakeFilterRepository()
        filterRepository.fetchError = .network("offline")
        let viewModel = ProjectOverviewViewModel(
            project: Project(id: -6, title: "Overdue work"),
            repository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: filterRepository,
            toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )

        await viewModel.load()

        #expect(viewModel.savedFilterQuery == nil)
        #expect(viewModel.loadState == .loaded)
    }
}
