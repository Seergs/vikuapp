@testable import Search
import VikunjaCore

final class FakeTaskRepository: TaskRepositoryProtocol, TaskSearchRepositoryProtocol, @unchecked Sendable {
    var searchError: VikunjaError?
    var searchDelay: Duration = .zero
    var onSearch: (@Sendable () async -> Void)?
    private(set) var searches: [TaskSearchQuery] = []

    func searchTasks(matching query: TaskSearchQuery) async throws -> [VikunjaTask] {
        searches.append(query)
        await onSearch?()
        try await Task.sleep(for: searchDelay)
        if let searchError {
            throw searchError
        }
        return query.filter(tasks: tasks, projects: [], labels: tasks.flatMap(\.labels))
    }

    var tasks: [VikunjaTask] = []
    var updateError: VikunjaError?
    var deleteError: VikunjaError?
    private(set) var updatedTasks: [VikunjaTask] = []
    private(set) var deletedIDs: [Int] = []

    func fetchTasks(projectID: EntityID) async throws -> [VikunjaTask] {
        tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: EntityID) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        if let updateError {
            throw updateError
        }
        updatedTasks.append(task)
        return task
    }

    func delete(id: EntityID) async throws {
        if let deleteError {
            throw deleteError
        }
        if let remoteID = id.remoteValue {
            deletedIDs.append(remoteID)
        }
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query: String) async throws -> [VikunjaTask] {
        tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []

    func fetchProjects() async throws -> [Project] {
        projects
    }

    func fetchProject(id: EntityID) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id: EntityID) async throws {
        projects.removeAll { $0.id == id }
    }
}

@MainActor
final class FakeToastPresenter: ToastPresenting {
    private(set) var shown: [(message: String, style: ToastStyle)] = []
    func show(_ message: String, style: ToastStyle) {
        shown.append((message, style))
    }
}

@MainActor
final class FakeHapticPresenter: HapticFeedbackPresenting {
    private(set) var played: [HapticStyle] = []
    func play(_ style: HapticStyle) {
        played.append(style)
    }
}

@MainActor
final class FakeSyntaxStore: QuickAddSyntaxStore {
    var syntax: QuickAddSyntax?
    init(_ syntax: QuickAddSyntax?) {
        self.syntax = syntax
    }

    func setSyntax(_ syntax: QuickAddSyntax?) {
        self.syntax = syntax
    }
}
