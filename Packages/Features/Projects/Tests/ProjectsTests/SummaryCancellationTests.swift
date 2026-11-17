import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor struct SummaryCancellationTests {
    private func repositories() -> (FakeProjectRepository, FakeTaskRepository) {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Parent"), Project(id: 2, title: "Child", parentProjectID: 1)]
        let tasks = FakeTaskRepository()
        tasks.tasks = [VikunjaTask(id: 1, title: "Saved", projectID: 2)]
        return (projects, tasks)
    }

    @Test func `cancelled list summary preserves loaded counters and their cache`() async {
        let (projects, tasks) = repositories()
        let toast = FakeToastPresenter()
        let cache = FakeProjectTaskSummaryCaching()
        let model = ProjectsListViewModel(
            syncTrigger: TestScreenSync(),
            localData: TestScreenSync(),
            repository: projects,
            taskRepository: tasks,
            filterRepository: FakeFilterRepository(),
            taskSummaryCache: cache,
            toastPresenter: toast,
        )
        await model.load()
        #expect(model.taskSummaries[2]?.total == 1)
        tasks.beforeFetchTasks = { id in
            if id == 2 {
                throw CancellationError()
            }
        }
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.taskSummaries[2]?.total == 1)
        #expect(cache.cachedTaskSummaries()[2]?.total == 1)
        #expect(toast.shownMessages.isEmpty)
    }

    @Test func `cancelled child summary preserves the project snapshot`() async {
        let (projects, tasks) = repositories()
        let toast = FakeToastPresenter()
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(),
            localData: TestScreenSync(),
            project: projects.projects[0],
            repository: tasks,
            bulkUpdateRepository: tasks,
            projectRepository: projects,
            labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(),
            filterRepository: FakeFilterRepository(),
            toastPresenter: toast,
            taskSortStore: FakeTaskSortStore(),
        )
        await model.load()
        #expect(model.subprojectTaskSummaries[2]?.total == 1)
        tasks.beforeFetchTasks = { id in
            if id == 2 {
                throw CancellationError()
            }
        }
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.subprojectTaskSummaries[2]?.total == 1)
        #expect(toast.shownMessages.isEmpty)
    }
}
