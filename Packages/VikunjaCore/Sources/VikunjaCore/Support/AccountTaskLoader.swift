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
    /// flattens them into one list. Cancellation and project-list failures
    /// propagate; other per-project failures contribute no tasks.
    public func loadAllTasks() async throws -> (tasks: [VikunjaTask], projectsByID: [EntityID: Project]) {
        try Task.checkCancellation()
        let projects = try await projectRepository.fetchProjects()
        try Task.checkCancellation()
        // Preserve local identities so unsynced tasks can resolve their
        // project for navigation, names, and colors before reaching the server.
        let projectsByID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0) },
        )
        let tasks = try await Self.fetchAllTasks(projects: projects, repository: taskRepository)
        try Task.checkCancellation()
        return (tasks, projectsByID)
    }

    private static func fetchAllTasks(
        projects: [Project],
        repository: TaskRepositoryProtocol,
    ) async throws -> [VikunjaTask] {
        try await withThrowingTaskGroup(of: [VikunjaTask].self) { group in
            // Vikunja lists virtual projects (Favorites, saved filters)
            // alongside real ones. Their tasks are views over tasks that
            // already live in a real project, so fetching them would show
            // every such task twice.
            for project in projects where project.kind == .project {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let tasks = try await repository.fetchTasks(projectID: project.id)
                        try Task.checkCancellation()
                        return tasks
                    } catch {
                        if error is CancellationError || Task.isCancelled {
                            throw CancellationError()
                        }
                        return []
                    }
                }
            }
            var allTasks: [VikunjaTask] = []
            for try await tasks in group {
                allTasks.append(contentsOf: tasks)
            }
            return allTasks
        }
    }
}
