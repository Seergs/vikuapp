import Foundation
@testable import Tasks
import Testing
import VikunjaCore
import VikuUI

@MainActor
struct TaskDetailViewModelTests {
    @Test
    func `starts with the task passed in at construction`() {
        let repository = FakeTaskRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 1)
        let viewModel = TaskDetailViewModel(
            task: task,
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        #expect(viewModel.task == task)
        #expect(viewModel.loadState == .idle)
    }

    @Test
    func `mark visible selects the tasks project for quick add and mark hidden releases it`() {
        let context = FakeQuickAddContext()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 4),
            project: Project(id: 4, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            quickAddContext: context,
        )

        viewModel.markVisible()
        #expect(context.preselectedProjectID == 4)

        viewModel.markHidden()
        #expect(context.preselectedProjectID == nil)
    }

    @Test
    func `load replaces the task with the repositorys fresher copy`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Write report", description: "Add the missing appendix", projectID: 1),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.task.description == "Add the missing appendix")
    }

    @Test
    func `load surfaces A friendly message on failure`() async {
        let repository = FakeTaskRepository()
        repository.fetchError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failure("Couldn't reach that server. Check the address and your connection."))
    }

    @Test
    func `toggle done persists the flipped state through the repository`() async {
        let repository = FakeTaskRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.toggleDone()

        #expect(viewModel.task.isDone == true)
    }

    @Test
    func `toggle done preserves relations the update response doesnt echo`() async {
        let repository = FakeTaskRepository()
        let task = VikunjaTask(
            id: 1,
            title: "Write report",
            isDone: false,
            projectID: 1,
            subtasks: [TaskRelation(id: 2, title: "Outline", isDone: true, projectID: 1)],
            dependsOn: [TaskRelation(id: 3, title: "Approve brief", isDone: false, projectID: 1)],
            blocks: [TaskRelation(id: 4, title: "Publish", isDone: false, projectID: 1)],
            otherRelations: [.related: [TaskRelation(id: 5, title: "Related memo", isDone: false, projectID: 1)]],
        )
        let viewModel = TaskDetailViewModel(
            task: task,
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.toggleDone()

        #expect(viewModel.task.isDone == true)
        #expect(viewModel.task.subtasks == task.subtasks)
        #expect(viewModel.task.dependsOn == task.dependsOn)
        #expect(viewModel.task.blocks == task.blocks)
        #expect(viewModel.task.otherRelations == task.otherRelations)
    }

    @Test
    func `toggle done reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.toggleDone()

        #expect(viewModel.task.isDone == false)
    }

    @Test
    func `completing a task plays a success haptic but un-completing does not`() async {
        let haptics = FakeHapticPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", isDone: false, projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            hapticPresenter: haptics,
        )

        await viewModel.toggleDone()
        #expect(haptics.played == [.success])

        await viewModel.toggleDone()
        #expect(haptics.played == [.success])
    }

    @Test
    func `set due date persists the chosen date`() async {
        let repository = FakeTaskRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)

        await viewModel.setDueDate(dueDate)

        #expect(viewModel.task.dueDate == dueDate)
    }

    @Test
    func `set due date reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setDueDate(Date())

        #expect(viewModel.task.dueDate == nil)
    }

    @Test
    func `set priority persists the chosen priority`() async {
        let repository = FakeTaskRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setPriority(.urgent)

        #expect(viewModel.task.priority == .urgent)
    }

    @Test
    func `set priority reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setPriority(.high)

        #expect(viewModel.task.priority == .unset)
    }

    @Test
    func `set title persists the new title`() async {
        let repository = FakeTaskRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setTitle("Write annual report")

        #expect(viewModel.task.title == "Write annual report")
    }

    @Test
    func `set title reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setTitle("Write annual report")

        #expect(viewModel.task.title == "Write report")
    }

    @Test
    func `set description persists the new description`() async {
        let repository = FakeTaskRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setDescription("Quarterly numbers and highlights.")

        #expect(viewModel.task.description == "Quarterly numbers and highlights.")
    }

    @Test
    func `set description reverts when the server rejects the update`() async {
        let repository = FakeTaskRepository()
        repository.updateError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", description: "Original", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.setDescription("Changed")

        #expect(viewModel.task.description == "Original")
    }

    @Test
    func `load all labels populates from the repository`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.labels = [Label(id: 1, title: "Design", hexColor: "8B5CF6")]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadAllLabels()

        #expect(viewModel.allLabels == labelRepository.labels)
    }

    @Test
    func `toggle label adds an unattached label and persists the association`() async {
        let labelRepository = FakeLabelRepository()
        let label = Label(id: 1, title: "Design", hexColor: "8B5CF6")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.toggleLabel(label)

        #expect(viewModel.task.labels == [label])
        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [1])
    }

    @Test
    func `toggle label removes an attached label and persists the association`() async {
        let labelRepository = FakeLabelRepository()
        let label = Label(id: 1, title: "Design", hexColor: "8B5CF6")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1, labels: [label]),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.toggleLabel(label)

        #expect(viewModel.task.labels.isEmpty)
        #expect(labelRepository.removedLabelIDs.map(\.labelID) == [1])
    }

    @Test
    func `toggle label reverts when the server rejects the association`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.addError = .network("offline")
        let label = Label(id: 1, title: "Design", hexColor: "8B5CF6")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.toggleLabel(label)

        #expect(viewModel.task.labels.isEmpty)
    }

    @Test
    func `create and add label creates then attaches the new label`() async {
        let labelRepository = FakeLabelRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.createAndAddLabel(title: "Urgent", hexColor: "EF4444")

        #expect(viewModel.task.labels.map(\.title) == ["Urgent"])
        #expect(viewModel.allLabels.map(\.title) == ["Urgent"])
        #expect(labelRepository.addedLabelIDs.count == 1)
    }

    @Test
    func `create and add label does nothing when creation fails`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.createError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: labelRepository,
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.createAndAddLabel(title: "Urgent", hexColor: "EF4444")

        #expect(viewModel.task.labels.isEmpty)
        #expect(viewModel.allLabels.isEmpty)
    }

    @Test
    func `add relation appends to the named field for subtask depends on and blocks`() async {
        let relationRepository = FakeTaskRelationRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        let subtask = TaskRelation(id: 2, title: "Outline", projectID: 1)
        let dependency = TaskRelation(id: 3, title: "Approve brief", projectID: 1)
        let blocked = TaskRelation(id: 4, title: "Publish", projectID: 1)

        await viewModel.addRelation(subtask, kind: .subtask)
        await viewModel.addRelation(dependency, kind: .blocked)
        await viewModel.addRelation(blocked, kind: .blocking)

        #expect(viewModel.task.subtasks == [subtask])
        #expect(viewModel.task.dependsOn == [dependency])
        #expect(viewModel.task.blocks == [blocked])
        #expect(relationRepository.addedRelations.map(\.kind) == [.subtask, .blocked, .blocking])
        #expect(relationRepository.addedRelations.map(\.otherTaskID) == [2, 3, 4])
    }

    @Test
    func `add relation appends to other relations for every other kind`() async {
        let relationRepository = FakeTaskRelationRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        let related = TaskRelation(id: 6, title: "Related memo", projectID: 1)

        await viewModel.addRelation(related, kind: .related)

        #expect(viewModel.task.otherRelations[.related] == [related])
    }

    @Test
    func `add relation reverts when the server rejects it`() async {
        let relationRepository = FakeTaskRelationRepository()
        relationRepository.addError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.addRelation(TaskRelation(id: 2, title: "Outline", projectID: 1), kind: .subtask)

        #expect(viewModel.task.subtasks.isEmpty)
    }

    @Test
    func `add relation shows A success toast`() async {
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        await viewModel.addRelation(TaskRelation(id: 2, title: "Outline", projectID: 1), kind: .subtask)

        #expect(toastPresenter.shownMessages.map(\.message) == ["Relation added"])
    }

    @Test
    func `add relation does not show A toast when the server rejects it`() async {
        let relationRepository = FakeTaskRelationRepository()
        relationRepository.addError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        await viewModel.addRelation(TaskRelation(id: 2, title: "Outline", projectID: 1), kind: .subtask)

        #expect(toastPresenter.shownMessages.isEmpty)
    }

    @Test
    func `remove relation drops from the named field and persists the removal`() async {
        let relationRepository = FakeTaskRelationRepository()
        let subtask = TaskRelation(id: 2, title: "Outline", projectID: 1)
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1, subtasks: [subtask]),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.removeRelation(subtask, kind: .subtask)

        #expect(viewModel.task.subtasks.isEmpty)
        #expect(relationRepository.removedRelations.map(\.otherTaskID) == [2])
    }

    @Test
    func `remove relation reverts when the server rejects it`() async {
        let relationRepository = FakeTaskRelationRepository()
        relationRepository.removeError = .network("offline")
        let subtask = TaskRelation(id: 2, title: "Outline", projectID: 1)
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1, subtasks: [subtask]),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: relationRepository,
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.removeRelation(subtask, kind: .subtask)

        #expect(viewModel.task.subtasks == [subtask])
    }

    @Test
    func `search tasks for relation excludes the task itself and already related tasks`() async {
        let repository = FakeTaskRepository()
        repository.searchResults = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Outline", projectID: 1),
            VikunjaTask(id: 3, title: "Approve brief", projectID: 1),
            VikunjaTask(id: 9, title: "Draft appendix", projectID: 1),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(
                id: 1,
                title: "Write report",
                projectID: 1,
                subtasks: [TaskRelation(id: 2, title: "Outline", projectID: 1)],
                dependsOn: [TaskRelation(id: 3, title: "Approve brief", projectID: 1)],
            ),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.searchTasksForRelation(query: "a")

        #expect(viewModel.relationSearchResults.map(\.id) == [9])
    }

    @Test
    func `search tasks for relation falls back to project suggestions for A blank query`() async {
        let repository = FakeTaskRepository()
        repository.searchResults = [VikunjaTask(id: 9, title: "Draft appendix", projectID: 1)]
        repository.tasks = [VikunjaTask(id: 8, title: "Outline appendix", projectID: 1)]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.searchTasksForRelation(query: "   ")

        #expect(viewModel.relationSearchResults.map(\.id) == [8])
    }

    @Test
    func `load relation suggestions populates from the current project excluding self and already related tasks`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Write report", projectID: 1),
            VikunjaTask(id: 2, title: "Outline", projectID: 1),
            VikunjaTask(id: 9, title: "Draft appendix", projectID: 1),
            VikunjaTask(id: 10, title: "Unrelated in another project", projectID: 2),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(
                id: 1,
                title: "Write report",
                projectID: 1,
                subtasks: [TaskRelation(id: 2, title: "Outline", projectID: 1)],
            ),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadRelationSuggestions()

        #expect(viewModel.relationSearchResults.map(\.id) == [9])
    }

    @Test
    func `search tasks for relation leaves results empty on failure`() async {
        let repository = FakeTaskRepository()
        repository.searchError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.searchTasksForRelation(query: "report")

        #expect(viewModel.relationSearchResults.isEmpty)
    }

    @Test
    func `load all projects populates from the repository`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 2, title: "Personal"), Project(id: 3, title: "Health")]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadAllProjects()

        #expect(viewModel.allProjects == projectRepository.projects)
    }

    @Test
    func `project title resolves the current project without loading all projects`() {
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        #expect(viewModel.projectTitle(forProjectID: 1) == "Work")
    }

    @Test
    func `project title resolves any loaded project`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 2, title: "Personal")]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadAllProjects()

        #expect(viewModel.projectTitle(forProjectID: 2) == "Personal")
        #expect(viewModel.projectTitle(forProjectID: 999) == nil)
    }

    @Test
    func `load comments populates from the repository`() async {
        let commentRepository = FakeTaskCommentRepository()
        let author = User(id: 2, username: "sam", name: "Sam")
        commentRepository.comments = [
            TaskComment(id: 1, comment: "Looks good", author: author, created: Date(), updated: Date()),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadComments()

        #expect(viewModel.comments == commentRepository.comments)
        #expect(viewModel.commentsLoadState == .loaded)
    }

    @Test
    func `load comments surfaces A friendly message on failure`() async {
        let commentRepository = FakeTaskCommentRepository()
        commentRepository.fetchError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadComments()

        let unreachable = ScreenLoadState<Void>.failure(
            "Couldn't reach that server. Check the address and your connection.",
        )
        #expect(viewModel.commentsLoadState == unreachable)
    }

    @Test
    func `load attachments populates from the repository`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        attachmentRepository.attachments = [
            TaskAttachment(
                id: 1,
                taskID: 1,
                fileName: "spec.pdf",
                mimeType: "application/pdf",
                sizeBytes: 2048,
                created: Date(),
                createdBy: User(id: 2, username: "sam"),
            ),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadAttachments()

        #expect(viewModel.attachments == attachmentRepository.attachments)
        #expect(viewModel.attachmentsLoadState == .loaded)
    }

    @Test
    func `load attachments surfaces A friendly message on failure`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        attachmentRepository.fetchError = .network("offline")
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadAttachments()

        let unreachable = ScreenLoadState<Void>.failure(
            "Couldn't reach that server. Check the address and your connection.",
        )
        #expect(viewModel.attachmentsLoadState == unreachable)
    }

    @Test
    func `upload attachment appends the created attachment and toasts success`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 7, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        await viewModel.uploadAttachment(data: Data("hello".utf8), fileName: "notes.txt", mimeType: "text/plain")

        #expect(viewModel.attachments.map(\.fileName) == ["notes.txt"])
        #expect(attachmentRepository.uploaded.map(\.taskID) == [7])
        #expect(attachmentRepository.uploaded.first?.size == 5)
        #expect(viewModel.isUploadingAttachment == false)
        #expect(toastPresenter.shownMessages.contains { $0.style == .success })
    }

    @Test
    func `upload attachment surfaces an error toast on failure`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        attachmentRepository.uploadError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 7, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        await viewModel.uploadAttachment(data: Data(), fileName: "x.bin", mimeType: "application/octet-stream")

        #expect(viewModel.attachments.isEmpty)
        #expect(viewModel.isUploadingAttachment == false)
        #expect(toastPresenter.shownMessages.contains { $0.style == .error })
    }

    @Test
    func `attachment data returns the repository bytes`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        attachmentRepository.downloadData = [5: Data("PDFBYTES".utf8)]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        let attachment = TaskAttachment(
            id: 5,
            taskID: 1,
            fileName: "spec.pdf",
            mimeType: "application/pdf",
            sizeBytes: 8,
            created: Date(),
            createdBy: User(id: 2, username: "sam"),
        )

        let data = await viewModel.attachmentData(for: attachment)

        #expect(data == Data("PDFBYTES".utf8))
        #expect(attachmentRepository.downloadedPreviewSizes == [nil])
    }

    @Test
    func `attachment data toasts and returns nil on failure`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        attachmentRepository.downloadError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )
        let attachment = TaskAttachment(
            id: 5,
            taskID: 1,
            fileName: "spec.pdf",
            mimeType: "application/pdf",
            sizeBytes: 8,
            created: Date(),
            createdBy: User(id: 2, username: "sam"),
        )

        let data = await viewModel.attachmentData(for: attachment)

        #expect(data == nil)
        #expect(toastPresenter.shownMessages.contains { $0.style == .error })
    }

    @Test
    func `delete attachment removes it optimistically`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        let first = TaskAttachment(
            id: 1, taskID: 1, fileName: "a.pdf", mimeType: "application/pdf", sizeBytes: 1,
            created: Date(), createdBy: User(id: 2, username: "sam"),
        )
        let second = TaskAttachment(
            id: 2, taskID: 1, fileName: "b.png", mimeType: "image/png", sizeBytes: 1,
            created: Date(), createdBy: User(id: 2, username: "sam"),
        )
        attachmentRepository.attachments = [first, second]
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )
        await viewModel.loadAttachments()

        await viewModel.deleteAttachment(first)

        #expect(viewModel.attachments.map(\.id) == [2])
        #expect(toastPresenter.shownMessages.contains { $0.style == .success })
    }

    @Test
    func `delete attachment rolls back and toasts on failure`() async {
        let attachmentRepository = FakeTaskAttachmentRepository()
        let attachment = TaskAttachment(
            id: 1, taskID: 1, fileName: "a.pdf", mimeType: "application/pdf", sizeBytes: 1,
            created: Date(), createdBy: User(id: 2, username: "sam"),
        )
        attachmentRepository.attachments = [attachment]
        attachmentRepository.deleteError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: attachmentRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )
        await viewModel.loadAttachments()

        await viewModel.deleteAttachment(attachment)

        #expect(viewModel.attachments.map(\.id) == [1])
        #expect(toastPresenter.shownMessages.contains { $0.style == .error })
    }

    @Test
    func `add comment appends the created comment`() async {
        let commentRepository = FakeTaskCommentRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.addComment("Sounds good")

        #expect(viewModel.comments.map(\.comment) == ["Sounds good"])
    }

    @Test
    func `add comment does nothing for blank text`() async {
        let commentRepository = FakeTaskCommentRepository()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.addComment("   ")

        #expect(viewModel.comments.isEmpty)
    }

    @Test
    func `add comment shows an error toast on failure`() async {
        let commentRepository = FakeTaskCommentRepository()
        commentRepository.addError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        await viewModel.addComment("Sounds good")

        #expect(viewModel.comments.isEmpty)
        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `delete comment removes it from the list`() async {
        let commentRepository = FakeTaskCommentRepository()
        let author = User(id: 1, username: "me")
        commentRepository.comments = [
            TaskComment(id: 1, comment: "Keep", author: author, created: Date(), updated: Date()),
            TaskComment(id: 2, comment: "Drop", author: author, created: Date(), updated: Date()),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.loadComments()

        await viewModel.deleteComment(commentRepository.comments[1])

        #expect(viewModel.comments.map(\.id) == [1])
    }

    @Test
    func `delete comment restores the list and shows an error toast on failure`() async {
        let commentRepository = FakeTaskCommentRepository()
        commentRepository.deleteError = .network("offline")
        let author = User(id: 1, username: "me")
        let doomed = TaskComment(id: 2, comment: "Drop", author: author, created: Date(), updated: Date())
        commentRepository.comments = [
            TaskComment(id: 1, comment: "Keep", author: author, created: Date(), updated: Date()),
            doomed,
        ]
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )
        await viewModel.loadComments()

        await viewModel.deleteComment(doomed)

        #expect(viewModel.comments.map(\.id) == [1, 2])
        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `edit comment replaces the comment with the server response`() async {
        let commentRepository = FakeTaskCommentRepository()
        let author = User(id: 1, username: "me")
        commentRepository.comments = [
            TaskComment(id: 1, comment: "Frist draft", author: author, created: Date(), updated: Date()),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.loadComments()

        await viewModel.editComment(viewModel.comments[0], newText: "  First draft  ")

        #expect(viewModel.comments.map(\.comment) == ["First draft"])
    }

    @Test
    func `edit comment does nothing for blank text`() async {
        let commentRepository = FakeTaskCommentRepository()
        let author = User(id: 1, username: "me")
        commentRepository.comments = [
            TaskComment(id: 1, comment: "Original", author: author, created: Date(), updated: Date()),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.loadComments()

        await viewModel.editComment(viewModel.comments[0], newText: "   ")

        #expect(viewModel.comments.map(\.comment) == ["Original"])
    }

    @Test
    func `edit comment keeps the original and shows an error toast on failure`() async {
        let commentRepository = FakeTaskCommentRepository()
        commentRepository.updateError = .network("offline")
        let author = User(id: 1, username: "me")
        commentRepository.comments = [
            TaskComment(id: 1, comment: "Original", author: author, created: Date(), updated: Date()),
        ]
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: commentRepository,
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )
        await viewModel.loadComments()

        await viewModel.editComment(viewModel.comments[0], newText: "Revised")

        #expect(viewModel.comments.map(\.comment) == ["Original"])
        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `move updates the tasks project and shows A success toast`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        let succeeded = await viewModel.move(to: Project(id: 2, title: "Personal"))

        #expect(succeeded == true)
        #expect(viewModel.task.projectID == 2)
        #expect(toastPresenter.shownMessages.last?.style == .success)
    }

    @Test
    func `move reverts and shows an error toast on failure`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        repository.updateError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        let succeeded = await viewModel.move(to: Project(id: 2, title: "Personal"))

        #expect(succeeded == false)
        #expect(viewModel.task.projectID == 1)
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }

    @Test
    func `loadAllProjects populates the move-picker candidates`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [
            Project(id: 1, title: "Work"),
            Project(id: 2, title: "Personal"),
            Project(id: 3, title: "Client A", parentProjectID: 2),
        ]
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: FakeTaskRepository(),
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.loadAllProjects()

        #expect(viewModel.allProjects.map(\.id) == [1, 2, 3])
    }

    @Test
    func `delete task shows A success toast`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        let succeeded = await viewModel.deleteTask()

        #expect(succeeded == true)
        #expect(toastPresenter.shownMessages.last?.style == .success)
    }

    @Test
    func `delete task shows an error toast on failure`() async {
        let repository = FakeTaskRepository()
        repository.tasks = [VikunjaTask(id: 1, title: "Write report", projectID: 1)]
        repository.deleteError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = TaskDetailViewModel(
            task: VikunjaTask(id: 1, title: "Write report", projectID: 1),
            project: Project(id: 1, title: "Work"),
            repository: repository,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(),
            attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: toastPresenter,
        )

        let succeeded = await viewModel.deleteTask()

        #expect(succeeded == false)
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }
}
