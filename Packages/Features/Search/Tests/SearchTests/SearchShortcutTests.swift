import Foundation
@testable import Search
import Testing
import VikunjaCore

@MainActor
struct SearchShortcutTests {
    private func viewModel(
        repository: FakeTaskRepository,
        syntax: FakeSyntaxStore = FakeSyntaxStore(.vikunja),
        projects: FakeProjectRepository = FakeProjectRepository(),
    ) -> SearchViewModel {
        SearchViewModel(
            taskRepository: repository,
            searchRepository: repository,
            projectRepository: projects,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: syntax,
        )
    }

    @Test(arguments: [QuickAddSyntax.vikunja, .todoist])
    func `search passes structured criteria using the configured dialect`(syntax: QuickAddSyntax) async {
        let repository = FakeTaskRepository()
        let model = viewModel(repository: repository, syntax: FakeSyntaxStore(syntax))
        model.query = "\(syntax.labelSigil)Bug \(syntax.projectSigil)Work \(syntax.priorityPrefix)3 login tomorrow"
        model.queryChanged()
        await model.searchTask?.value
        #expect(repository.searches == [TaskSearchQuery(
            text: "login tomorrow", projectName: "Work", labelNames: ["Bug"], priority: syntax.priority(forLevel: 3),
        )])
        #expect(model.state.isLoaded)
    }

    @Test func `disabled shortcuts stay literal and changing syntax permits the same query`() async {
        let repository = FakeTaskRepository()
        let store = FakeSyntaxStore(nil)
        let model = viewModel(repository: repository, syntax: store)
        model.query = "*Bug login"
        model.queryChanged()
        await model.searchTask?.value
        #expect(repository.searches.last == TaskSearchQuery(text: "*Bug login"))
        store.setSyntax(.vikunja)
        model.queryChanged()
        await model.searchTask?.value
        #expect(repository.searches.last == TaskSearchQuery(text: "login", labelNames: ["Bug"]))
        #expect(repository.searches.count == 2)
    }

    @Test func `rapid typing cancels superseded searches and clearing returns to idle`() async {
        let repository = FakeTaskRepository()
        let model = viewModel(repository: repository)
        model.query = "*Bug old"
        model.queryChanged()
        let oldSearch = model.searchTask
        model.query = "*Bug new"
        model.queryChanged()
        await model.searchTask?.value
        await oldSearch?.value
        #expect(repository.searches.map(\.text) == ["new"])
        model.query = " \n "
        model.queryChanged()
        #expect(model.state == .idle)
        #expect(repository.searches.count == 1)
    }

    @Test func `a read failure preserves input and the same query can be retried`() async {
        let repository = FakeTaskRepository()
        repository.searchError = .network("Unavailable")
        let model = viewModel(repository: repository)
        model.query = "*Bug login"
        model.queryChanged()
        await model.searchTask?.value
        if case .failure = model.state {} else {
            Issue.record("Expected search failure")
        }
        #expect(model.query == "*Bug login")
        repository.searchError = nil
        model.queryChanged()
        await model.searchTask?.value
        #expect(model.state.isLoaded)
        #expect(repository.searches.count == 2)
    }

    @Test func `leaving the screen cancels a debounced search`() async {
        let repository = FakeTaskRepository()
        let model = viewModel(repository: repository)
        model.query = "*Bug"
        model.queryChanged()
        model.cancelSearch()
        await model.searchTask?.value
        #expect(repository.searches.isEmpty)
        #expect(model.state == .idle)
    }

    @Test func `offline created projects remain available for rendering search results`() async {
        let repository = FakeTaskRepository()
        let projects = FakeProjectRepository()
        let project = Project(id: .local(UUID()), title: "Work")
        projects.projects = [project]
        repository.tasks = [VikunjaTask(id: .local(UUID()), title: "Login", projectID: project.id)]
        let model = viewModel(repository: repository, projects: projects)
        model.query = "login"
        model.queryChanged()
        await model.searchTask?.value
        #expect(model.state.value == repository.tasks)
        #expect(model.projectsByID[project.id] == project)
    }

    @Test func `a slow search keeps results visible and a newer query cancels it`() async {
        let repository = FakeTaskRepository()
        let previous = VikunjaTask(id: 1, title: "Old", projectID: 1)
        let latest = VikunjaTask(id: 2, title: "New", projectID: 1)
        repository.tasks = [previous, latest]
        repository.searchDelay = .seconds(20)
        let started = AsyncStream<Void>.makeStream()
        repository.onSearch = { started.continuation.yield(()) }
        defer { started.continuation.finish() }
        let model = viewModel(repository: repository)
        model.state = .loaded([previous])
        model.query = "Old"
        model.queryChanged()
        let oldSearch = model.searchTask
        for await _ in started.stream {
            break
        }
        #expect(model.state.value == [previous])
        repository.searchDelay = .zero
        model.query = "New"
        model.queryChanged()
        await model.searchTask?.value
        await oldSearch?.value
        #expect(model.state.value == [latest])
    }

    @Test func `an unfinished cancelled search resumes on returning to the screen`() async {
        let repository = FakeTaskRepository()
        let model = viewModel(repository: repository)
        model.query = "Login"
        model.queryChanged()
        model.cancelSearch()
        await model.searchTask?.value
        await model.preload()
        await model.searchTask?.value
        #expect(repository.searches.map(\.text) == ["Login"])
        #expect(model.state.isLoaded)
    }

    @Test func `returning to loaded results does not automatically refresh them`() async {
        let repository = FakeTaskRepository()
        let model = viewModel(repository: repository)
        model.query = "Login"
        model.queryChanged()
        await model.searchTask?.value
        model.cancelSearch()
        repository.tasks = [VikunjaTask(id: 1, title: "Login", projectID: 1)]
        await model.preload()
        #expect(model.searchTask == nil)
        #expect(repository.searches.count == 1)
        #expect(model.state.value?.isEmpty == true)
    }
}
