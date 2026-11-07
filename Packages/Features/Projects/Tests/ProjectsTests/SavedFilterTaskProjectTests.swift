import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct SavedFilterTaskProjectTests {
    private func fixture(project: Project = Project(id: -2, title: "Open tasks")) -> (
        viewModel: ProjectOverviewViewModel, projects: FakeProjectRepository,
    ) {
        let projects = FakeProjectRepository()
        projects.projects = [
            project,
            Project(id: 1, title: "Work", hexColor: "ff0000"),
            Project(id: 2, title: "Personal", hexColor: "00ff00"),
        ]
        let tasks = FakeTaskRepository()
        tasks.tasks = [
            VikunjaTask(id: 10, title: "First", projectID: 1),
            VikunjaTask(id: 11, title: "Second", projectID: 2),
        ]
        if project.kind == .savedFilter {
            tasks.taskIDsByProjectID[project.id] = Set(tasks.tasks.map(\.id))
        }
        return (ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(), project: project,
            repository: tasks, bulkUpdateRepository: tasks, projectRepository: projects,
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(), toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        ), projects)
    }

    @Test func `filter tasks resolve their own name and color from local catalogs while offline`() async {
        let context = fixture()
        await context.viewModel.load()

        #expect(context.viewModel.loadState == .loaded)
        let owners = context.viewModel.tasks.compactMap { context.viewModel.project(for: $0) }
        #expect(owners.map(\.title) == ["Work", "Personal"])
        #expect(owners.map(\.hexColor) == ["ff0000", "00ff00"])
        #expect(context.viewModel.tasks.map { context.viewModel.taskProject(for: $0).id } == [1, 2])
    }

    @Test func `missing owner does not hide a task or attribute it to the filter`() async {
        let context = fixture()
        context.projects.projects.removeAll { $0.id == 2 }
        await context.viewModel.load()

        #expect(context.viewModel.tasks.count == 2)
        let task = context.viewModel.tasks[1]
        #expect(context.viewModel.project(for: task) == nil)
        #expect(context.viewModel.taskProject(for: task).id == task.projectID)
        #expect(context.viewModel.taskProject(for: task).title.isEmpty)
    }

    @Test func `catalog failure preserves tasks and cached owners then refresh recovers metadata`() async {
        let context = fixture()
        await context.viewModel.load()
        context.projects.fetchError = .network("offline")
        await context.viewModel.load()
        #expect(context.viewModel.loadState == .loaded)
        #expect(context.viewModel.project(for: context.viewModel.tasks[0])?.title == "Work")

        context.projects.fetchError = nil
        context.projects.projects[1].title = "Renamed"
        context.projects.projects[1].hexColor = "0000ff"
        await context.viewModel.load()
        #expect(context.viewModel.project(for: context.viewModel.tasks[0])?.title == "Renamed")
        #expect(context.viewModel.project(for: context.viewModel.tasks[0])?.hexColor == "0000ff")
    }

    @Test func `initial catalog failure still presents filter tasks`() async {
        let context = fixture()
        context.projects.fetchError = .network("unavailable")
        await context.viewModel.load()
        #expect(context.viewModel.loadState == .loaded)
        #expect(context.viewModel.tasks.count == 2)
        #expect(context.viewModel.project(for: context.viewModel.tasks[0]) == nil)
    }

    @Test func `regular project resolves its refreshed metadata without a badge catalog`() async {
        let context = fixture(project: Project(id: 1, title: "Work"))
        context.projects.projects[0].title = "Renamed"
        await context.viewModel.load()
        #expect(context.viewModel.project(for: context.viewModel.tasks[0])?.title == "Renamed")
        #expect(context.viewModel.projectsByID.isEmpty)
    }

    @Test func `slow cancelled catalog refresh retains visible owners`() async {
        let context = fixture()
        await context.viewModel.load()
        let gate = TaskProjectCatalogGate()
        context.projects.beforeFetchProjects = { await gate.block() }
        context.projects.projects[1].title = "Cancelled rename"
        let refresh = Task { await context.viewModel.load() }
        await gate.waitUntilBlocked()
        #expect(context.viewModel.loadState == .loaded)
        #expect(context.viewModel.project(for: context.viewModel.tasks[0])?.title == "Work")
        refresh.cancel()
        await gate.release()
        await refresh.value
        #expect(context.viewModel.project(for: context.viewModel.tasks[0])?.title == "Work")
    }
}

private actor TaskProjectCatalogGate {
    private var blocked = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var suspended: CheckedContinuation<Void, Never>?

    func block() async {
        await withCheckedContinuation { continuation in
            suspended = continuation
            blocked = true
            arrival?.resume()
            arrival = nil
        }
    }

    func waitUntilBlocked() async {
        if blocked {
            return
        }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}
