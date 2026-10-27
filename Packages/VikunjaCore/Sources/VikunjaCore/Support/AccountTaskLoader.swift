import Foundation

/// Loads every task the account can see, across every project, as one flat
/// list plus a project lookup — the "nothing scopes the fetch to a single
/// project" pattern the Today and Calendar screens share. Each screen wraps
/// the result in its own load-state enum; this only does the fetching.
///
/// Virtual projects (negative ids: Favorites, saved filters) are skipped so
/// tasks aren't returned once per real project and again per virtual one. A
/// project that hasn't synced yet (offline-created, `.local` id) is still
/// queried — it can't have any tasks on the server, but it may well have
/// tasks created offline under it, which `fetchTasks(projectID:)` resolves
/// locally when the repository backing it supports that.
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
        // Keyed by the server id, for callers that look up a task's project
        // by `task.projectID.remoteValue`. A project without one yet
        // (offline-created, not synced) is excluded — there's nothing to
        // key it by until it syncs, same as the task itself showing no
        // project name/color until then.
        let projectsByID = Dictionary(
            uniqueKeysWithValues: projects.compactMap { project in
                project.id.remoteValue.map { ($0, project) }
            },
        )
        let tasks = await Self.fetchAllTasks(projects: projects, repository: taskRepository)
        return (tasks, projectsByID)
    }

    private static func fetchAllTasks(
        projects: [Project],
        repository: TaskRepositoryProtocol,
    ) async -> [VikunjaTask] {
        await withTaskGroup(of: [VikunjaTask].self) { group in
            // Vikunja lists virtual projects (Favorites, saved filters)
            // alongside real ones. Their tasks are views over tasks that
            // already live in a real project, so fetching them would show
            // every such task twice.
            for project in projects where project.kind == .project {
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
