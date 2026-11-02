import Foundation
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
    func `indexes unsynced projects alongside remote projects`() async throws {
        let localProject = Project(id: .local(UUID()), title: "Offline", hexColor: "#123456")
        let remoteProject = Project(id: 1, title: "Synced")
        let projects = FakeProjectRepository()
        projects.projects = [remoteProject, localProject]
        let task = VikunjaTask(id: .local(UUID()), title: "Offline task", projectID: localProject.id)
        let tasks = FakeTaskRepository()
        tasks.tasks = [task]
        let loader = AccountTaskLoader(taskRepository: tasks, projectRepository: projects)

        let result = try await loader.loadAllTasks()

        #expect(result.tasks == [task])
        #expect(result.projectsByID[task.projectID] == localProject)
        #expect(result.projectsByID[remoteProject.id] == remoteProject)
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
    func `skips virtual projects so favorited tasks aren't returned twice`() async throws {
        let projects = FakeProjectRepository()
        projects.projects = [
            Project(id: 1, title: "Work"),
            Project(id: -1, title: "Favorites"),
            Project(id: -2, title: "Saved filter"),
        ]
        let tasks = FakeTaskRepository()
        tasks.tasks = [VikunjaTask(id: 10, title: "A", projectID: 1)]
        let loader = AccountTaskLoader(taskRepository: tasks, projectRepository: projects)

        let result = try await loader.loadAllTasks()

        #expect(tasks.fetchedProjectIDs == [1])
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
