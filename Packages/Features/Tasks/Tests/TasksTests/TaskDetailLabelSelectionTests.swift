import Foundation
@testable import Tasks
import Testing
import VikunjaCore

private struct LabelSyncChange: LocalDataObserving {
    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream {
            $0.yield(())
            $0.finish()
        }
    }
}

@MainActor
struct TaskDetailLabelSelectionTests {
    @Test
    func `toggling an attached label with different display fields removes it`() async {
        let attached = Label(id: 10, title: "Urgent", hexColor: "ef4444")
        let pickerLabel = Label(id: 10, title: "Urgent", hexColor: "EF4444")
        let labels = FakeLabelRepository()
        let viewModel = makeViewModel(labels: labels, taskLabels: [attached])

        await viewModel.toggleLabel(pickerLabel)

        #expect(viewModel.task.labels.isEmpty)
        #expect(labels.addedLabelIDs.isEmpty)
        #expect(labels.removedLabelIDs.map(\.labelID) == [attached.id])
    }

    @Test
    func `failed removal restores the attached label despite different display fields`() async {
        let attached = Label(id: 10, title: "Urgent", hexColor: "ef4444")
        let labels = FakeLabelRepository()
        labels.removeError = .network("offline")
        let viewModel = makeViewModel(labels: labels, taskLabels: [attached])

        await viewModel.toggleLabel(Label(id: 10, title: "Renamed", hexColor: "EF4444"))

        #expect(viewModel.task.labels == [attached])
        #expect(labels.addedLabelIDs.isEmpty)
    }

    @Test
    func `sync keeps a newly created picker label selected after its ID becomes remote`() async throws {
        let labels = FakeLabelRepository()
        labels.createdLabelID = .local(UUID())
        let repository = FakeTaskRepository()
        let viewModel = makeViewModel(labels: labels, repository: repository)
        await viewModel.loadAllLabels()
        await viewModel.createAndAddLabel(title: "Urgent", hexColor: "EF4444")
        let created = try #require(viewModel.allLabels.first)
        #expect(viewModel.task.labels == [created])
        #expect(labels.addedLabelIDs.count == 1)

        let synced = Label(id: 100, title: "Urgent", hexColor: "ef4444")
        labels.labels = [synced]
        repository.tasks = [VikunjaTask(id: 1, title: "Report", projectID: 1, labels: [synced])]
        await viewModel.observeLocalChanges()

        #expect(viewModel.allLabels == [synced])
        #expect(viewModel.task.labels == [synced])
        try await viewModel.toggleLabel(#require(viewModel.allLabels.first))
        #expect(viewModel.task.labels.isEmpty)
        #expect(labels.addedLabelIDs.count == 1)
        #expect(labels.removedLabelIDs.map(\.labelID) == [synced.id])
    }

    @Test
    func `failed attachment leaves the created label available for retry`() async throws {
        let labels = FakeLabelRepository()
        labels.addError = .network("offline")
        let viewModel = makeViewModel(labels: labels)

        await viewModel.createAndAddLabel(title: "Urgent", hexColor: "EF4444")

        let created = try #require(viewModel.allLabels.first)
        #expect(viewModel.task.labels.isEmpty)
        labels.addError = nil
        await viewModel.toggleLabel(created)
        #expect(viewModel.task.labels == [created])
        #expect(labels.labels.count == 1)
        #expect(labels.addedLabelIDs.map(\.labelID) == [created.id])
    }

    private func makeViewModel(
        labels: FakeLabelRepository,
        repository: FakeTaskRepository = FakeTaskRepository(),
        taskLabels: [Label] = [],
    ) -> TaskDetailViewModel {
        TaskDetailViewModel(
            syncTrigger: TestScreenSync(), localData: LabelSyncChange(),
            task: VikunjaTask(id: 1, title: "Report", projectID: 1, labels: taskLabels),
            project: Project(id: 1, title: "Work"), repository: repository,
            labelRepository: labels, relationRepository: FakeTaskRelationRepository(),
            commentRepository: FakeTaskCommentRepository(), attachmentRepository: FakeTaskAttachmentRepository(),
            projectRepository: FakeProjectRepository(), toastPresenter: FakeToastPresenter(),
        )
    }
}
