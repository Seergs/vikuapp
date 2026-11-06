import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct BulkCompletionTests {
    private func model(repository: FakeTaskRepository, toast: FakeToastPresenter) async -> ProjectOverviewViewModel {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work")]
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            project: Project(id: 1, title: "Work"), repository: repository, bulkUpdateRepository: repository,
            projectRepository: projects, labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(), filterRepository: FakeFilterRepository(),
            toastPresenter: toast, taskSortStore: FakeTaskSortStore(),
        )
        await model.load()
        return model
    }

    private func repository() -> FakeTaskRepository {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Pending", projectID: 1),
            VikunjaTask(id: 2, title: "Completed", isDone: true, projectID: 1),
            VikunjaTask(id: 3, title: "Hidden", projectID: 1),
        ]
        return repository
    }

    @Test(arguments: [true, false])
    func `completing or reopening a mixed selection leaves hidden tasks untouched`(isDone: Bool) async {
        let repository = repository()
        let toast = FakeToastPresenter()
        let model = await model(repository: repository, toast: toast)
        model.bulkSelection.begin()
        model.bulkSelection.selectAll(model.tasks)
        await model.setSelectedCompletion(isDone: isDone, visibleTasks: Array(model.tasks.prefix(2)))
        #expect(model.tasks.map(\.isDone) == [isDone, isDone, false])
        #expect(repository.completionCalls.count == 1)
        #expect(repository.completionCalls.first?.ids == [1, 2])
        #expect(repository.completionCalls.first?.isDone == isDone)
        #expect(!model.bulkSelection.isSelecting)
        #expect(toast.shownMessages.count == 1)
    }

    @Test func `a failed local write keeps state and selection for retry`() async {
        let repository = repository()
        repository.completionError = VikunjaError.notFound
        let toast = FakeToastPresenter()
        let model = await model(repository: repository, toast: toast)
        model.bulkSelection.begin()
        model.bulkSelection.selectAll(model.tasks)
        await model.setSelectedCompletion(isDone: true, visibleTasks: model.tasks)
        #expect(model.tasks.map(\.isDone) == [false, true, false])
        #expect(model.bulkSelection.selectedIDs == [1, 2, 3])
        #expect(!model.bulkSelection.isPerformingAction)
        #expect(toast.shownMessages.first?.style == .error)
        repository.completionError = nil
        await model.setSelectedCompletion(isDone: true, visibleTasks: model.tasks)
        #expect(model.tasks.map(\.isDone) == [true, true, true])
        #expect(!model.bulkSelection.isSelecting)
    }

    @Test func `slow acceptance preserves other fields refreshed during the write`() async {
        let repository = repository()
        let model = await model(repository: repository, toast: FakeToastPresenter())
        model.bulkSelection.begin()
        model.bulkSelection.toggle(1)
        repository.beforeCompletion = {
            let isBusy = await model.bulkSelection.isPerformingAction
            #expect(isBusy)
            repository.tasks[0].title = "Renamed during write"
            await model.load()
        }
        await model.setSelectedCompletion(isDone: true, visibleTasks: model.tasks)
        #expect(model.tasks[0].isDone)
        #expect(model.tasks[0].title == "Renamed during write")
        #expect(!model.bulkSelection.isPerformingAction)
    }

    @Test func `a local observation that removes a task is never undone by the completion response`() async {
        let repository = repository()
        let model = await model(repository: repository, toast: FakeToastPresenter())
        model.bulkSelection.begin()
        model.bulkSelection.toggle(1)
        repository.beforeCompletion = {
            let saved = repository.tasks
            repository.tasks = []
            await model.load()
            repository.tasks = saved
        }
        await model.setSelectedCompletion(isDone: true, visibleTasks: model.tasks)
        #expect(model.tasks.isEmpty)
        #expect(!model.bulkSelection.isSelecting)
    }

    @Test func `an individual local write finishes before a bulk operation can start`() async {
        let repository = repository()
        let model = await model(repository: repository, toast: FakeToastPresenter())
        repository.beforeUpdate = {
            let pending = await model.hasPendingCompletionWrites
            #expect(pending)
            await MainActor.run {
                model.bulkSelection.begin()
                model.bulkSelection.toggle(1)
            }
            await model.setSelectedCompletion(isDone: false, visibleTasks: model.tasks)
            #expect(repository.completionCalls.isEmpty)
            await MainActor.run { model.bulkSelection.reset() }
        }
        await model.toggleDone(model.tasks[0])
        #expect(!model.hasPendingCompletionWrites)
    }

    @Test func `selection blocks an individual completion that was dispatched earlier`() async {
        let repository = repository()
        let model = await model(repository: repository, toast: FakeToastPresenter())
        model.bulkSelection.begin()
        model.bulkSelection.toggle(1)
        repository.beforeUpdate = { Issue.record("Individual mutation during selection") }
        await model.toggleDone(model.tasks[0])
        #expect(model.tasks[0].isDone == false)
        #expect(!model.hasPendingCompletionWrites)
    }

    @Test func `cancelled acceptance retains the selected tasks without a failure toast`() async {
        let repository = repository()
        repository.completionError = CancellationError()
        let toast = FakeToastPresenter()
        let model = await model(repository: repository, toast: toast)
        model.bulkSelection.begin()
        model.bulkSelection.toggle(1)
        await model.setSelectedCompletion(isDone: true, visibleTasks: model.tasks)
        #expect(model.tasks[0].isDone == false)
        #expect(model.bulkSelection.selectedIDs == [1])
        #expect(toast.shownMessages.isEmpty)
    }
}
