import Foundation
import VikunjaCore

/// Minimal in-memory `AccountStoreProtocol`. Only the reads the loader/intent
/// use are meaningful; the mutating calls are enough to set up a test.
actor FakeAccountStore: AccountStoreProtocol {
    private var accounts: [InstanceAccount] = []
    private var tokens: [UUID: String] = [:]
    private var activeID: UUID?
    var activeAccountError: VikunjaError?
    var tokenError: VikunjaError?

    init(account: InstanceAccount? = nil, token: String? = nil) {
        if let account {
            self.accounts = [account]
            self.activeID = account.id
            if let token {
                tokens[account.id] = token
            }
        }
    }

    func fetchAccounts() throws -> [InstanceAccount] {
        accounts
    }

    func activeAccount() throws -> InstanceAccount? {
        if let activeAccountError {
            throw activeAccountError
        }
        return accounts.first { $0.id == activeID }
    }

    func addAccount(_ account: InstanceAccount, token: String) throws {
        accounts.append(account)
        tokens[account.id] = token
        activeID = account.id
    }

    func updateAccount(_ account: InstanceAccount, token: String?) throws {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        }
        if let token {
            tokens[account.id] = token
        }
    }

    func removeAccount(id: InstanceAccount.ID) throws {
        accounts.removeAll { $0.id == id }
        tokens[id] = nil
    }

    func setActiveAccount(id: InstanceAccount.ID) throws {
        activeID = id
    }

    func token(forAccountID id: InstanceAccount.ID) throws -> String? {
        if let tokenError {
            throw tokenError
        }
        return tokens[id]
    }

    func clearToken(for id: UUID) {
        tokens[id] = nil
    }
}

final class FakeProjectRepository: ProjectRepositoryProtocol, @unchecked Sendable {
    var projects: [Project] = []
    var fetchError: VikunjaError?

    func fetchProjects() async throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return projects
    }

    func fetchProject(id: Int) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return project
    }

    func create(_ project: Project) async throws -> Project {
        project
    }

    func update(_ project: Project) async throws -> Project {
        project
    }

    func delete(id: Int) async throws {
        projects.removeAll { $0.id == id }
    }
}

final class FakeTaskRepository: TaskRepositoryProtocol, @unchecked Sendable {
    var tasks: [VikunjaTask] = []
    var failingProjectIDs: Set<Int> = []
    var fetchTasksError: VikunjaError?

    func fetchTasks(projectID: Int) async throws -> [VikunjaTask] {
        if let fetchTasksError {
            throw fetchTasksError
        }
        if failingProjectIDs.contains(projectID) {
            throw VikunjaError.network("offline")
        }
        return tasks.filter { $0.projectID == projectID }
    }

    func fetchTask(id: Int) async throws -> VikunjaTask {
        guard let task = tasks.first(where: { $0.id == id }) else { throw VikunjaError.notFound }
        return task
    }

    func create(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func update(_ task: VikunjaTask) async throws -> VikunjaTask {
        task
    }

    func delete(id: Int) async throws {
        tasks.removeAll { $0.id == id }
    }

    func searchTasks(query _: String) async throws -> [VikunjaTask] {
        tasks
    }
}

/// `InstanceClientFactoryProtocol` that hands back preconfigured fakes.
/// Only the project/task factories are exercised by the widget.
struct FakeClientFactory: InstanceClientFactoryProtocol {
    let projectRepository: FakeProjectRepository
    let taskRepository: FakeTaskRepository

    func makeCapabilityProvider(baseURL _: URL) -> CapabilityProvider {
        fatalError("unused")
    }

    func makeAuthService(baseURL _: URL) -> AuthServiceProtocol {
        fatalError("unused")
    }

    func makeProjectRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> ProjectRepositoryProtocol {
        projectRepository
    }

    func makeTaskRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskRepositoryProtocol {
        taskRepository
    }

    func makeLabelRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> LabelRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskRelationRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskRelationRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskCommentRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskCommentRepositoryProtocol {
        fatalError("unused")
    }

    func makeTaskAttachmentRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> TaskAttachmentRepositoryProtocol {
        fatalError("unused")
    }

    func makeUserRepository(
        baseURL _: URL, tokenProvider _: @escaping @Sendable () async throws -> String?,
    ) -> UserRepositoryProtocol {
        fatalError("unused")
    }
}

enum TestSupport {
    static func account() -> InstanceAccount {
        InstanceAccount(displayName: "Home", baseURL: URL(string: "https://tasks.example.com")!)
    }

    static func tempCacheDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("viku-widget-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
