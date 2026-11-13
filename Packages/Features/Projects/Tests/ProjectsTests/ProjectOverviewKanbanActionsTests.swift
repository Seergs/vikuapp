import Foundation
@testable import Projects
import Testing
import VikunjaCore

/// Boards can contain tasks excluded from the local List query. Both presentations
/// must edit canonical tasks without changing the other's query membership.
@MainActor
struct ProjectOverviewKanbanActionsTests {
    @Test(arguments: [false, true])
    func `priority and due date edit current fields without inserting board tasks into the list`(isListed: Bool) async {
        let fixture = Fixture(isListed: isListed)
        await fixture.viewModel.load()
        let captured = fixture.task
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

        await fixture.viewModel.setPriority(captured, to: .urgent)
        await fixture.viewModel.setDueDate(captured, to: dueDate)

        #expect(fixture.repository.tasks[0].priority == .urgent)
        #expect(fixture.repository.tasks[0].dueDate == dueDate)
        #expect(fixture.repository.tasks[0].title == captured.title)
        #expect(fixture.repository.tasks[0].projectID == captured.projectID)
        #expect(fixture.viewModel.tasks.count == (isListed ? 1 : 0))

        await fixture.viewModel.setDueDate(captured, to: nil)

        #expect(fixture.repository.tasks[0].dueDate == nil)
        #expect(fixture.repository.tasks[0].priority == .urgent)
    }

    @Test(arguments: [false, true])
    func `rejected edits preserve task fields and can be retried`(isListed: Bool) async {
        let fixture = Fixture(isListed: isListed)
        await fixture.viewModel.load()
        fixture.repository.updateError = .offline

        await fixture.viewModel.setPriority(fixture.task, to: .urgent)
        await fixture.viewModel.setDueDate(fixture.task, to: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(fixture.repository.tasks == [fixture.task])
        #expect(fixture.viewModel.tasks == (isListed ? [fixture.task] : []))

        fixture.repository.updateError = nil
        await fixture.viewModel.setPriority(fixture.task, to: .urgent)

        #expect(fixture.repository.tasks[0].priority == .urgent)
        #expect(fixture.viewModel.tasks.count == (isListed ? 1 : 0))
    }

    @Test
    func `label actions use canonical membership for tasks absent from the list`() async {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let label = Label(id: 3, title: "Work", hexColor: "ff0000")

        await fixture.viewModel.toggleLabel(fixture.task, label)

        #expect(fixture.labels.addedLabelIDs.map(\.taskID) == [fixture.task.id])
        #expect(fixture.viewModel.tasks.isEmpty)

        // Simulate the canonical local write made by the real label repository.
        fixture.repository.tasks[0].labels = [label]
        await fixture.viewModel.toggleLabel(fixture.task, label)

        #expect(fixture.labels.removedLabelIDs.map(\.labelID) == [label.id])
        #expect(fixture.labels.removedLabelIDs.map(\.taskID) == [fixture.task.id])
    }

    @Test(arguments: [false, true])
    func `creating a label reports attachment success independently of list membership`(rejectAttachment: Bool) async {
        let fixture = Fixture()
        await fixture.viewModel.load()
        fixture.labels.addError = rejectAttachment ? .offline : nil

        let created = await fixture.viewModel.createAndAddLabel(fixture.task, title: "Work", hexColor: "ff0000")

        #expect((created == nil) == rejectAttachment)
        #expect(fixture.labels.addedLabelIDs.count == (rejectAttachment ? 0 : 1))
        #expect(fixture.viewModel.tasks.isEmpty)
        #expect(fixture.viewModel.allLabels.map(\.title) == ["Work"])
    }

    @Test(arguments: [false, true])
    func `relation actions reach the owning task and report failures outside the list`(rejectRelation: Bool) async {
        let fixture = Fixture()
        await fixture.viewModel.load()
        fixture.relations.addError = rejectRelation ? .offline : nil
        let relation = TaskRelation(id: 9, title: "Related", projectID: 2)

        await fixture.viewModel.addRelation(relation, kind: .related, to: fixture.task)

        #expect(fixture.relations.addedRelations.map(\.taskID) == (rejectRelation ? [] : [fixture.task.id]))
        #expect(fixture.toast.shownMessages.last?.style == (rejectRelation ? .error : .success))
        #expect(fixture.viewModel.tasks.isEmpty)
    }

    @Test
    func `actions on a deleted board task report failure without resurrecting it`() async {
        let fixture = Fixture()
        await fixture.viewModel.load()
        fixture.repository.tasks = []

        await fixture.viewModel.setPriority(fixture.task, to: .urgent)
        await fixture.viewModel.toggleLabel(fixture.task, Label(id: 3, title: "Work", hexColor: "ff0000"))

        #expect(fixture.repository.updatedTasks.isEmpty)
        #expect(fixture.labels.addedLabelIDs.isEmpty)
        #expect(fixture.viewModel.tasks.isEmpty)
        #expect(fixture.toast.shownMessages.count == 2)
        #expect(fixture.toast.shownMessages.allSatisfy { $0.style == .error })
    }

    @Test
    func `move and delete support board tasks without adding them to the list`() async {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let destination = Project(id: 2, title: "Other")
        fixture.repository.updateError = .offline

        await fixture.viewModel.move(fixture.task, to: destination)
        #expect(fixture.repository.tasks[0].projectID == fixture.task.projectID)
        #expect(fixture.toast.shownMessages.last?.style == .error)

        fixture.repository.updateError = nil
        await fixture.viewModel.move(fixture.task, to: destination)
        #expect(fixture.repository.tasks[0].projectID == destination.id)
        #expect(fixture.viewModel.tasks.isEmpty)

        fixture.repository.deleteError = .offline
        await fixture.viewModel.delete(fixture.task)
        #expect(fixture.repository.tasks.count == 1)
        #expect(fixture.toast.shownMessages.last?.style == .error)

        fixture.repository.deleteError = nil
        await fixture.viewModel.delete(fixture.task)
        #expect(fixture.repository.tasks.isEmpty)
        #expect(fixture.viewModel.tasks.isEmpty)
    }

    @MainActor
    private struct Fixture {
        let task = VikunjaTask(id: .local(UUID()), title: "Board task", priority: .low, projectID: 1)
        let repository = FakeTaskRepository()
        let labels = FakeLabelRepository()
        let relations = FakeTaskRelationRepository()
        let toast = FakeToastPresenter()
        let viewModel: ProjectOverviewViewModel

        init(isListed: Bool = false) {
            let project = Project(id: -2, title: "Filter")
            let projects = FakeProjectRepository()
            projects.projects = [project, Project(id: 1, title: "Owner")]
            repository.tasks = [task]
            repository.taskIDsByProjectID[project.id] = isListed ? [task.id] : []
            self.viewModel = ProjectOverviewViewModel(
                syncTrigger: TestScreenSync(), localData: TestScreenSync(),
                project: project, repository: repository, bulkUpdateRepository: repository,
                projectRepository: projects, labelRepository: labels, relationRepository: relations,
                filterRepository: FakeFilterRepository(), toastPresenter: toast,
                taskSortStore: FakeTaskSortStore(),
            )
        }
    }
}
