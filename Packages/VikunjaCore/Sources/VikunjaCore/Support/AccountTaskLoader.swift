import Foundation

/// Loads every task the account can see, across every project, as one flat
/// list plus a project lookup — the "nothing scopes the fetch to a single
/// project" pattern the Today and Calendar screens share. Each screen wraps
/// the result in its own load-state enum; this only does the fetching.
///
/// A project whose task fetch fails is dropped from the result rather than
/// failing the whole load, so one unreadable project can't blank the screen.
public struct AccountTaskLoader: Sendable {
    private let taskRepository: TaskRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol

    public init(
        taskRepository: TaskRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
    ) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
    }

    /// Fetches the project list, then every project's tasks concurrently and
    /// flattens them into one list. Throws only when the project-list fetch
    /// itself fails; a single project's task-fetch failure is swallowed (that
    /// project just contributes no tasks).
    public func loadAllTasks() async throws -> (tasks: [VikunjaTask], projectsByID: [Int: Project]) {
        let projects = try await projectRepository.fetchProjects()
        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let tasks = await Self.fetchAllTasks(projects: projects, repository: taskRepository)
        return (tasks, projectsByID)
    }

    private static func fetchAllTasks(
        projects: [Project],
        repository: TaskRepositoryProtocol,
    ) async -> [VikunjaTask] {
        await withTaskGroup(of: [VikunjaTask].self) { group in
            for project in projects {
                group.addTask {
                    await (try? repository.fetchTasks(projectID: project.id)) ?? []
                }
            }
            var allTasks: [VikunjaTask] = []
            for await tasks in group {
                allTasks.append(contentsOf: tasks)
            }
            return allTasks
        }
    }
}
