import Testing
import VikunjaCore
@testable import VikuUI

@MainActor
struct DuplicateTaskViewModelTests {
    private func makeSource(
        id: Int = 1,
        title: String = "Ship release",
        projectID: Int = 7,
        priority: VikunjaTask.Priority = .high,
        labels: [Label] = [],
        dependsOn: [TaskRelation] = [],
        blocks: [TaskRelation] = [],
        otherRelations: [RelationKind: [TaskRelation]] = [:],
    ) -> VikunjaTask {
        VikunjaTask(
            id: id,
            title: title,
            description: "notes",
            dueDate: .distantFuture,
            priority: priority,
            projectID: projectID,
            labels: labels,
            dependsOn: dependsOn,
            blocks: blocks,
            otherRelations: otherRelations,
        )
    }

    private func makeViewModel(
        source: VikunjaTask,
        sourceProject: Project = Project(id: 7, title: "Release"),
        taskRepository: FakeTaskRepository = FakeTaskRepository(),
        labelRepository: FakeLabelRepository = FakeLabelRepository(),
        relationRepository: FakeTaskRelationRepository = FakeTaskRelationRepository(),
        projectRepository: FakeProjectRepository = FakeProjectRepository(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
        hapticPresenter: FakeHapticPresenter = FakeHapticPresenter(),
    ) -> DuplicateTaskViewModel {
        DuplicateTaskViewModel(
            source: source,
            sourceProject: sourceProject,
            taskRepository: taskRepository,
            labelRepository: labelRepository,
            relationRepository: relationRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )
    }

    @Test
    func `pre-fills the form from the source task with A copy suffix`() {
        let viewModel = makeViewModel(source: makeSource())

        #expect(viewModel.title == "Ship release (copy)")
        #expect(viewModel.selectedProjectID == 7)
        #expect(viewModel.priority == .high)
        #expect(viewModel.canSave == true)
    }

    @Test
    func `cannot save with A blank title`() {
        let viewModel = makeViewModel(source: makeSource())
        viewModel.title = "   "

        #expect(viewModel.canSave == false)
    }

    @Test
    func `load exposes non-archived projects ordered by position`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Later", isArchived: false, position: 2),
            Project(id: 2, title: "Archived", isArchived: true, position: 0),
            Project(id: 3, title: "First", isArchived: false, position: 1),
        ]
        let viewModel = makeViewModel(source: makeSource(), projectRepository: projectRepository)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.projects.map(\.id) == [3, 1])
    }

    @Test
    func `duplicate creates A new task with the edited fields`() async {
        let taskRepository = FakeTaskRepository()
        let viewModel = makeViewModel(source: makeSource(), taskRepository: taskRepository)
        viewModel.title = "  Ship hotfix  "
        viewModel.selectedProjectID = 9
        viewModel.priority = .urgent

        let created = await viewModel.duplicate()

        #expect(created?.task.id != 1)
        #expect(created?.task.title == "Ship hotfix")
        #expect(created?.task.projectID == 9)
        #expect(created?.task.priority == .urgent)
        #expect(created?.task.description == "notes")
        #expect(taskRepository.tasks.contains { $0.id == created?.task.id })
    }

    @Test
    func `duplicate returns the project the copy landed in`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 9, title: "Hotfixes")]
        let viewModel = makeViewModel(source: makeSource(), projectRepository: projectRepository)
        await viewModel.load()
        viewModel.selectedProjectID = 9

        let created = await viewModel.duplicate()

        #expect(created?.project.id == 9)
        #expect(created?.project.title == "Hotfixes")
    }

    @Test
    func `duplicate falls back to the source project when the list is unavailable`() async {
        let viewModel = makeViewModel(
            source: makeSource(projectID: 7),
            sourceProject: Project(id: 7, title: "Release"),
        )

        let created = await viewModel.duplicate()

        #expect(created?.project.id == 7)
        #expect(created?.project.title == "Release")
    }

    @Test
    func `duplicate copies labels onto the new task when enabled`() async {
        let labelRepository = FakeLabelRepository()
        let source = makeSource(labels: [
            Label(id: 11, title: "urgent", hexColor: "EF4444"),
            Label(id: 12, title: "backend", hexColor: "3B82F6"),
        ])
        let viewModel = makeViewModel(source: source, labelRepository: labelRepository)

        let created = await viewModel.duplicate()

        #expect(Set(labelRepository.addedLabelIDs.map(\.labelID)) == [11, 12])
        #expect(labelRepository.addedLabelIDs.allSatisfy { $0.taskID == created?.task.id })
    }

    @Test
    func `duplicate skips labels when the toggle is off`() async {
        let labelRepository = FakeLabelRepository()
        let source = makeSource(labels: [Label(id: 11, title: "urgent", hexColor: "EF4444")])
        let viewModel = makeViewModel(source: source, labelRepository: labelRepository)
        viewModel.copyLabels = false

        _ = await viewModel.duplicate()

        #expect(labelRepository.addedLabelIDs.isEmpty)
    }

    @Test
    func `duplicate replays relations but not subtasks`() async {
        let relationRepository = FakeTaskRelationRepository()
        let source = makeSource(
            dependsOn: [TaskRelation(id: 20, title: "Design sign-off", projectID: 7)],
            blocks: [TaskRelation(id: 21, title: "Announce", projectID: 7)],
            otherRelations: [.related: [TaskRelation(id: 22, title: "Retro", projectID: 7)]],
        )
        var source2 = source
        source2.subtasks = [TaskRelation(id: 99, title: "Sub", projectID: 7)]
        let viewModel = makeViewModel(source: source2, relationRepository: relationRepository)

        let created = await viewModel.duplicate()

        let added = relationRepository.addedRelations
        #expect(added.allSatisfy { $0.taskID == created?.task.id })
        #expect(Set(added.map(\.otherTaskID)) == [20, 21, 22])
        #expect(added.contains { $0.kind == .blocked && $0.otherTaskID == 20 })
        #expect(added.contains { $0.kind == .blocking && $0.otherTaskID == 21 })
        #expect(added.contains { $0.kind == .related && $0.otherTaskID == 22 })
        #expect(!added.contains { $0.kind == .subtask })
    }

    @Test
    func `duplicate shows A toast and plays A success haptic`() async {
        let toastPresenter = FakeToastPresenter()
        let hapticPresenter = FakeHapticPresenter()
        let viewModel = makeViewModel(
            source: makeSource(),
            toastPresenter: toastPresenter,
            hapticPresenter: hapticPresenter,
        )

        _ = await viewModel.duplicate()

        #expect(toastPresenter.shownMessages.first?.message == "Task duplicated")
        #expect(toastPresenter.shownMessages.first?.style == .success)
        #expect(hapticPresenter.played == [.success])
    }

    @Test
    func `duplicate surfaces A friendly message when the create fails`() async {
        let taskRepository = FakeTaskRepository()
        taskRepository.createError = .network("offline")
        let viewModel = makeViewModel(source: makeSource(), taskRepository: taskRepository)

        let created = await viewModel.duplicate()

        #expect(created == nil)
        #expect(viewModel.saveErrorMessage == "Couldn't reach that server. Check the address and your connection.")
        #expect(viewModel.isSaving == false)
    }

    @Test
    func `toggle visibility follows what the source actually carries`() {
        let bare = makeViewModel(source: makeSource())
        #expect(bare.hasLabelsToCopy == false)
        #expect(bare.hasRelationsToCopy == false)

        let rich = makeViewModel(source: makeSource(
            labels: [Label(id: 1, title: "x", hexColor: "EF4444")],
            blocks: [TaskRelation(id: 2, title: "y", projectID: 7)],
        ))
        #expect(rich.hasLabelsToCopy == true)
        #expect(rich.hasRelationsToCopy == true)
    }
}
