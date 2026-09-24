import Foundation
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
    func `set due date persists the new due date through the repository`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        let newDate = Date(timeIntervalSince1970: 0)

        await viewModel.setDueDate(viewModel.tasks[0], to: newDate)

        #expect(viewModel.tasks[0].dueDate == newDate)
    }

    @Test
    func `set due date reverts when the server rejects the update`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        let original = VikunjaTask(id: 1, title: "Write report", dueDate: Date(timeIntervalSince1970: 0), projectID: 1)
        taskRepository.tasks = [original]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        taskRepository.updateError = .network("offline")

        await viewModel.setDueDate(viewModel.tasks[0], to: nil)

        #expect(viewModel.tasks[0].dueDate == original.dueDate)
    }

    @Test
    func `toggle label adds A label through the label repository`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let labelRepository = FakeLabelRepository()
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        let label = Label(id: 5, title: "Urgent", hexColor: "ff0000")

        await viewModel.toggleLabel(viewModel.tasks[0], label)

        #expect(viewModel.tasks[0].labels == [label])
        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [5])
    }

    @Test
    func `toggle label removes an already attached label`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        let label = Label(id: 5, title: "Urgent", hexColor: "ff0000")
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1, labels: [label])]
        let labelRepository = FakeLabelRepository()
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.toggleLabel(viewModel.tasks[0], label)

        #expect(viewModel.tasks[0].labels.isEmpty)
        #expect(labelRepository.removedLabelIDs.map(\.labelID) == [5])
    }

    @Test
    func `toggle label reverts when the server rejects it`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let labelRepository = FakeLabelRepository()
        labelRepository.addError = .network("offline")
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        let label = Label(id: 5, title: "Urgent", hexColor: "ff0000")

        await viewModel.toggleLabel(viewModel.tasks[0], label)

        #expect(viewModel.tasks[0].labels.isEmpty)
    }

    @Test
    func `create and add label creates then attaches the new label`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let labelRepository = FakeLabelRepository()
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.createAndAddLabel(viewModel.tasks[0], title: "Urgent", hexColor: "ff0000")

        #expect(viewModel.allLabels.map(\.title) == ["Urgent"])
        #expect(viewModel.tasks[0].labels.map(\.title) == ["Urgent"])
        #expect(labelRepository.addedLabelIDs.count == 1)
    }

    @Test
    func `add relation persists through the relation repository and shows A success toast`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let relationRepository = FakeTaskRelationRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            toastPresenter: toastPresenter,
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
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let relationRepository = FakeTaskRelationRepository()
        relationRepository.addError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.addRelation(
            TaskRelation(id: 9, title: "Draft appendix", projectID: 1), kind: .related, to: viewModel.tasks[0],
        )

        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `search tasks for relation excludes the task itself and already related tasks`() async throws {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [
            VikunjaTask(
                id: 1, title: "Write report", projectID: 1,
                dependsOn: [TaskRelation(id: 3, title: "Approve brief", projectID: 1)],
            ),
            VikunjaTask(id: 3, title: "Approve brief", projectID: 1),
            VikunjaTask(id: 9, title: "Draft appendix", projectID: 1),
        ]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        let task = try #require(viewModel.tasks.first { $0.id == 1 })

        await viewModel.searchTasksForRelation(for: task, query: "a")

        #expect(viewModel.relationSearchResults.map(\.id) == [9])
    }

    @Test
    func `load relation suggestions populates from the tasks own project excluding self`() async throws {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Work"), Project(id: 2, title: "Personal")]
        let taskRepository = FakeTaskRepository()
        taskRepository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Outline", projectID: 1),
            VikunjaTask(id: 9, title: "Unrelated", projectID: 2),
        ]
        let viewModel = TodayViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        let task = try #require(viewModel.tasks.first { $0.id == 1 })

        await viewModel.loadRelationSuggestions(for: task)

        #expect(viewModel.relationSearchResults.map(\.id) == [2])
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
