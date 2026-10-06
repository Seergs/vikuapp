@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddShortcutTests {
    private func makeViewModel(
        syntax: QuickAddSyntax?,
        taskRepository: FakeTaskRepository = FakeTaskRepository(),
        projects: [Project] = [Project(id: 1, title: "Compras"), Project(id: 2, title: "Trabajo")],
        selectedProjectID: Int? = nil,
    ) async -> QuickAddTaskViewModel {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = projects
        let viewModel = QuickAddTaskViewModel(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
        )
        await viewModel.load()
        viewModel.selectedProjectID = selectedProjectID
        return viewModel
    }

    @Test
    func `a todoist project shortcut sets the project and leaves the title clean`() async {
        let viewModel = await makeViewModel(syntax: .todoist)
        viewModel.input = "Leche #Compras"

        #expect(viewModel.selectedProjectID == 1)
        #expect(viewModel.parsed.title == "Leche")
        #expect(viewModel.canSave)
    }

    @Test
    func `a vikunja project shortcut is ignored under the todoist dialect`() async {
        let viewModel = await makeViewModel(syntax: .todoist)
        viewModel.input = "Leche +Compras"

        #expect(viewModel.selectedProjectID == nil)
        #expect(viewModel.parsed.title == "Leche +Compras")
        #expect(viewModel.canSave == false)
    }

    @Test
    func `a shortcut overrides the picked project`() async {
        let viewModel = await makeViewModel(syntax: .vikunja, selectedProjectID: 2)
        viewModel.input = "Leche +Compras"

        #expect(viewModel.selectedProjectID == 1)
        #expect(viewModel.selectedProject?.id == 1)
    }

    @Test
    func `the picked project stays when the shortcut does not match`() async {
        let viewModel = await makeViewModel(syntax: .vikunja, selectedProjectID: 2)
        viewModel.input = "Leche +Nope"

        #expect(viewModel.selectedProjectID == 2)
        #expect(viewModel.parsed.title == "Leche +Nope")
        #expect(viewModel.shortcutChips.count == 1)
    }

    @Test
    func `a matched shortcut leaves nothing unresolved`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.input = "Leche +Compras !2"

        #expect(viewModel.shortcutChips.isEmpty)
    }

    @Test
    func `an ambiguous shortcut is unresolved and not applied`() async {
        let viewModel = await makeViewModel(
            syntax: .vikunja,
            projects: [Project(id: 1, title: "Dup"), Project(id: 2, title: "dup")],
        )
        viewModel.input = "Leche +dup"

        #expect(viewModel.selectedProjectID == nil)
        #expect(viewModel.shortcutChips.count == 1)
    }

    @Test
    func `picking a project writes it into the title`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.input = "Leche +Trabajo"

        viewModel.pickProject(Project(id: 1, title: "Compras"))

        #expect(viewModel.input == "Leche +Compras")
        #expect(viewModel.selectedProjectID == 1)
    }

    @Test
    func `clearing the project removes its shortcut from the title`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.input = "Leche +Compras"

        viewModel.pickProject(nil)

        #expect(viewModel.input == "Leche")
        #expect(viewModel.selectedProjectID == nil)
    }

    @Test
    func `picking a priority writes it into the title with the dialect's symbol`() async {
        let viewModel = await makeViewModel(syntax: .todoist)

        viewModel.pickPriority(.high)

        #expect(viewModel.input == "p2")
        #expect(viewModel.priority == .high)
    }

    @Test
    func `the default project is not written into the title`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Compras")]
        let viewModel = QuickAddTaskViewModel(
            accountDefaultProjectID: 1,
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: .vikunja),
        )
        viewModel.input = "Leche"

        await viewModel.load()

        #expect(viewModel.selectedProjectID == 1)
        #expect(viewModel.input == "Leche")
    }

    @Test
    func `a manual pick survives until its shortcut text changes`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.input = "Leche +Compras"
        #expect(viewModel.selectedProjectID == 1)

        viewModel.selectedProjectID = 2
        viewModel.input = "Leche +Compras con pan"
        #expect(viewModel.selectedProjectID == 2)

        viewModel.input = "Leche +Trabajo"
        #expect(viewModel.selectedProjectID == 2)
    }

    @Test
    func `a manual priority pick survives until its shortcut text changes`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.input = "Leche !3"
        viewModel.priority = .low

        viewModel.input = "Leche !3 mañana"
        #expect(viewModel.priority == .low)

        viewModel.input = "Leche !4"
        #expect(viewModel.priority == .urgent)
    }

    @Test
    func `a project shortcut typed before the projects load applies once they arrive`() async {
        let projectRepository = FakeProjectRepository()
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: .vikunja),
        )
        viewModel.input = "Leche +Compras"
        #expect(viewModel.selectedProjectID == nil)

        projectRepository.projects = [Project(id: 1, title: "Compras")]
        await viewModel.load()

        #expect(viewModel.selectedProjectID == 1)
    }

    @Test
    func `a priority shortcut overrides the chips`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.priority = .low
        viewModel.input = "Leche !4"

        #expect(viewModel.priority == .urgent)
    }

    @Test
    func `the chips apply when there is no priority shortcut`() async {
        let viewModel = await makeViewModel(syntax: .vikunja)
        viewModel.priority = .medium
        viewModel.input = "Leche"

        #expect(viewModel.priority == .medium)
    }

    @Test
    func `save sends the parsed title, project and priority`() async {
        let taskRepository = FakeTaskRepository()
        let viewModel = await makeViewModel(syntax: .todoist, taskRepository: taskRepository)
        viewModel.input = "  Leche   p1  #Trabajo "

        let created = await viewModel.save()

        #expect(created?.title == "Leche")
        #expect(created?.projectID == 2)
        #expect(created?.priority == .urgent)
    }

    @Test
    func `a title made only of shortcuts cannot be saved`() async {
        let viewModel = await makeViewModel(syntax: .vikunja, selectedProjectID: 1)
        viewModel.input = "!3"

        #expect(viewModel.canSave == false)
    }

    @Test
    func `without a syntax store shortcuts are off`() async {
        let projectRepository = FakeProjectRepository()
        projectRepository.projects = [Project(id: 1, title: "Compras")]
        let viewModel = QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: projectRepository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()
        viewModel.input = "Leche +Compras"

        #expect(viewModel.selectedProjectID == nil)
        #expect(viewModel.parsed.tokens.isEmpty)
    }

    @Test
    func `with shortcuts off a saved title keeps its symbols and inner spacing`() async {
        let taskRepository = FakeTaskRepository()
        let viewModel = await makeViewModel(syntax: nil, taskRepository: taskRepository, selectedProjectID: 1)
        viewModel.input = "  Leche  !3 #Compras  "

        let created = await viewModel.save()

        #expect(created?.title == "Leche  !3 #Compras")
        #expect(created?.priority == .unset)
        #expect(created?.projectID == 1)
    }
}

@MainActor
final class FakeQuickAddSyntaxStore: QuickAddSyntaxStore {
    private(set) var syntax: QuickAddSyntax?

    init(syntax: QuickAddSyntax?) {
        self.syntax = syntax
    }

    func setSyntax(_ syntax: QuickAddSyntax?) {
        self.syntax = syntax
    }
}
