@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddLabelTests {
    private func makeViewModel(
        labels: [Label] = [Label(id: 10, title: "hogar", hexColor: "ff0000")],
        labelRepository: FakeLabelRepository = FakeLabelRepository(),
        taskRepository: FakeTaskRepository = FakeTaskRepository(),
        toastPresenter: FakeToastPresenter = FakeToastPresenter(),
    ) async -> QuickAddTaskViewModel {
        labelRepository.labels = labels
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Compras")]
        let viewModel = QuickAddTaskViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            toastPresenter: toastPresenter,
            syntaxStore: FakeQuickAddSyntaxStore(syntax: .todoist),
            labelRepository: labelRepository,
        )
        await viewModel.load()
        viewModel.selectedProjectID = 1
        return viewModel
    }

    @Test
    func `an existing label is attached and kept out of the title`() async {
        let labelRepository = FakeLabelRepository()
        let viewModel = await makeViewModel(labelRepository: labelRepository)
        viewModel.input = "Leche @hogar"

        let created = await viewModel.save()

        #expect(created?.title == "Leche")
        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [10])
        #expect(labelRepository.addedLabelIDs.first?.taskID == created?.id)
        #expect(labelRepository.labels.count == 1)
    }

    @Test
    func `an unknown label is created, then attached to the task`() async {
        let labelRepository = FakeLabelRepository()
        let viewModel = await makeViewModel(labelRepository: labelRepository)
        viewModel.input = "Leche @compras @hogar"

        let created = await viewModel.save()

        #expect(labelRepository.labels.map(\.title) == ["hogar", "compras"])
        #expect(labelRepository.addedLabelIDs.map(\.labelID) == [10, 100])
        #expect(labelRepository.addedLabelIDs.allSatisfy { $0.taskID == created?.id })
    }

    @Test
    func `a new label shows a chip before saving`() async {
        let viewModel = await makeViewModel()
        viewModel.input = "Leche @compras"

        #expect(viewModel.shortcutChips.count == 1)
        #expect(viewModel.shortcutChips.first?.resolution == .newLabel("compras"))
    }

    @Test
    func `an existing label gets no chip`() async {
        let viewModel = await makeViewModel()
        viewModel.input = "Leche @hogar"

        #expect(viewModel.shortcutChips.isEmpty)
    }

    @Test
    func `a label shortcut is refused when the labels did not load`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.fetchError = .network("offline")
        let taskRepository = FakeTaskRepository()
        let viewModel = QuickAddTaskViewModel(
            taskRepository: taskRepository,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: .todoist),
            labelRepository: labelRepository,
        )
        await viewModel.load()
        viewModel.selectedProjectID = 1
        viewModel.input = "Leche @hogar"

        let created = await viewModel.save()

        #expect(created == nil)
        #expect(labelRepository.addedLabelIDs.isEmpty)
        #expect(viewModel.saveErrorMessage != nil)
    }

    @Test
    func `a failed label creation creates no task`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.createError = .network("offline")
        let taskRepository = FakeTaskRepository()
        let viewModel = await makeViewModel(labelRepository: labelRepository, taskRepository: taskRepository)
        viewModel.input = "Leche @compras"

        let created = await viewModel.save()

        #expect(created == nil)
        #expect(viewModel.saveErrorMessage != nil)
    }

    @Test
    func `a failed attach still creates the task and says so`() async {
        let labelRepository = FakeLabelRepository()
        labelRepository.addError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = await makeViewModel(labelRepository: labelRepository, toastPresenter: toastPresenter)
        viewModel.input = "Leche @hogar"

        let created = await viewModel.save()

        #expect(created != nil)
        #expect(toastPresenter.shownMessages.last?.style == .error)
    }
}
