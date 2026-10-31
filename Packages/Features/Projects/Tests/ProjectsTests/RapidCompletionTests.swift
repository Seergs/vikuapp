import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct RapidCompletionTests {
    @Test
    func `concurrent completions stay stable and cancellation rolls back only its own task`() async {
        let projects = FakeProjectRepository()
        let project = Project(id: 1, title: "Project")
        projects.projects = [project]
        let repository = FakeTaskRepository()
        let first = VikunjaTask(id: 1, title: "First", projectID: 1)
        let second = VikunjaTask(id: 2, title: "Second", projectID: 1)
        repository.tasks = [first, second]
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(), project: project,
            repository: repository, projectRepository: projects, labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(), filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(), taskSortStore: FakeTaskSortStore(),
        )
        await model.load()
        let firstGate = CompletionReadGate()
        let secondGate = CompletionReadGate()
        repository.beforeUpdate = {
            await firstGate.suspend()
            try Task.checkCancellation()
        }
        let firstToggle = Task { await model.toggleDone(first) }
        await firstGate.waitUntilEntered()
        repository.beforeUpdate = { await secondGate.suspend() }
        let secondToggle = Task { await model.toggleDone(second) }
        await secondGate.waitUntilEntered()
        await model.load()
        #expect(model.tasks.map(\.isDone) == [true, true])
        await secondGate.release()
        await secondToggle.value
        await model.load()
        #expect(model.tasks.map(\.isDone) == [true, true])
        firstToggle.cancel()
        await firstGate.release()
        await firstToggle.value
        #expect(model.tasks.map(\.isDone) == [false, true])
        repository.beforeUpdate = nil
    }

    @Test
    func `a snapshot read before the write completes cannot overwrite the saved completion`() async {
        let projects = FakeProjectRepository()
        let project = Project(id: 1, title: "Project")
        projects.projects = [project]
        let repository = FakeTaskRepository()
        let task = VikunjaTask(id: 1, title: "Task", projectID: 1)
        repository.tasks = [task]
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(), project: project,
            repository: repository, projectRepository: projects, labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(), filterRepository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(), taskSortStore: FakeTaskSortStore(),
        )
        await model.load()
        let writeGate = CompletionReadGate()
        let readGate = CompletionReadGate()
        repository.beforeUpdate = { await writeGate.suspend() }
        let toggle = Task { await model.toggleDone(task) }
        await writeGate.waitUntilEntered()
        // load() has captured the old tasks before fetching subprojects.
        projects.beforeFetchProjects = { await readGate.suspend() }
        let reload = Task { await model.load() }
        await readGate.waitUntilEntered()
        await writeGate.release()
        await toggle.value
        #expect(model.tasks.first?.isDone == true)
        await readGate.release()
        await reload.value
        #expect(model.tasks.first?.isDone == true)
        repository.beforeUpdate = nil
        projects.beforeFetchProjects = nil
    }

    @Test(arguments: [true, false])
    func `a local reload preserves a pending completion until success or rollback`(succeeds: Bool) async {
        let projects = FakeProjectRepository()
        let project = Project(id: 1, title: "Project")
        projects.projects = [project]
        let repository = FakeTaskRepository()
        let first = VikunjaTask(id: 1, title: "First", projectID: 1)
        let second = VikunjaTask(id: 2, title: "Second", projectID: 1)
        repository.tasks = [first, second]
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            project: project, repository: repository, projectRepository: projects,
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(), toastPresenter: FakeToastPresenter(),
            taskSortStore: FakeTaskSortStore(),
        )
        await model.load()
        await model.toggleDone(first)
        // These fakes need not persist updates; seed the first saved edit.
        repository.tasks[0].isDone = true
        repository.updateError = succeeds ? nil : .network("Write failed")
        repository.beforeUpdate = {
            let optimistic = await model.tasks.map(\.isDone)
            #expect(optimistic == [true, true])
            repository.tasks[1].title = "Renamed during the write"
            await model.load()
            let reloaded = await model.tasks.map(\.isDone)
            #expect(reloaded == [true, true])
        }
        await model.toggleDone(second)
        #expect(model.tasks.map(\.isDone) == [true, succeeds])
        #expect(model.tasks[1].title == "Renamed during the write")
        repository.beforeUpdate = nil
        repository.tasks[1].isDone = succeeds
        await model.load()
        #expect(model.tasks.map(\.isDone) == [true, succeeds])
    }
}

private actor CompletionReadGate {
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var suspended: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspended = continuation
            entered = true
            arrival?.resume()
            arrival = nil
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}
