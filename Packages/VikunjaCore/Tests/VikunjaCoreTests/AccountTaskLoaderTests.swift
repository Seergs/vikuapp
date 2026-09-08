import Testing
@testable import VikunjaCore

@Suite("AccountTaskLoader")
struct AccountTaskLoaderTests {
    @Test
    func `merges every project's tasks and indexes the projects`() async throws {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work"), Project(id: 2, title: "Home")]
        let tasks = FakeTaskRepository()
        tasks.tasks = [
            VikunjaTask(id: 10, title: "A", projectID: 1),
            VikunjaTask(id: 20, title: "B", projectID: 2),
        ]
        let loader = AccountTaskLoader(taskRepository: tasks, projectRepository: projects)

        let result = try await loader.loadAllTasks()

        #expect(Set(result.tasks.map(\.id)) == [10, 20])
        #expect(result.projectsByID[1]?.title == "Work")
        #expect(result.projectsByID[2]?.title == "Home")
    }

    @Test
    func `drops a project whose task fetch fails rather than throwing`() async throws {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work"), Project(id: 2, title: "Home")]
        let tasks = FakeTaskRepository()
        tasks.tasks = [
            VikunjaTask(id: 10, title: "A", projectID: 1),
            VikunjaTask(id: 20, title: "B", projectID: 2),
        ]
        tasks.failingProjectIDs = [2]
        let loader = AccountTaskLoader(taskRepository: tasks, projectRepository: projects)

        let result = try await loader.loadAllTasks()

        #expect(result.tasks.map(\.id) == [10])
    }

    @Test
    func `propagates a project-list fetch failure`() async {
        let projects = FakeProjectRepository()
        projects.fetchError = .network("offline")
        let loader = AccountTaskLoader(taskRepository: FakeTaskRepository(), projectRepository: projects)

        await #expect(throws: VikunjaError.self) {
            _ = try await loader.loadAllTasks()
        }
    }
}
