import Foundation
import VikunjaCore

/// Produces the Today widget's `TodayWidgetState` for one timeline refresh:
/// resolves the active account, pulls every project's tasks concurrently
/// (dropping a project whose fetch fails, exactly like `TodayViewModel`),
/// buckets them via `TodayDigest`, caches the result, and falls back to the
/// cached snapshot when the network fails.
///
/// Takes its dependencies as `VikunjaCore` protocols so it can be tested with
/// fakes; `VikuWidgetEnvironment` wires the real ones.
public struct TodaySnapshotLoader: Sendable {
    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let cache: TodaySnapshotCache
    private let taskLimit: Int
    private let now: @Sendable () -> Date
    /// Resolves a currently-valid bearer credential for `account`. Defaults
    /// to a direct Keychain read (today's behavior); `VikuWidgetEnvironment`
    /// passes one backed by `PasswordSessionRefresher` so a password
    /// account's JWT gets refreshed here too, not just from the app.
    private let tokenResolver: @Sendable (InstanceAccount) async throws -> String?

    public init(
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        cache: TodaySnapshotCache,
        taskLimit: Int = VikuWidgetConfig.taskLimit,
        now: @escaping @Sendable () -> Date = { Date() },
        tokenResolver: (@Sendable (InstanceAccount) async throws -> String?)? = nil,
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.cache = cache
        self.taskLimit = taskLimit
        self.now = now
        self.tokenResolver = tokenResolver ?? { try? await accountStore.token(forAccountID: $0.id) }
    }

    public func loadState() async -> TodayWidgetState {
        let account = try? await accountStore.activeAccount()
        var token: String?
        if let account {
            // A `.sessionExpired` refresh failure has nothing more useful to
            // do here than fall back to the cache below — the widget can't
            // present a "sign in again" prompt of its own.
            token = try? await tokenResolver(account)
        }

        guard let account, let token, !token.isEmpty else {
            // The widget process can't reach the credentials — keychain
            // sharing isn't in effect on this OS/provisioning (notably the
            // iOS Simulator). Render whatever the app last wrote to the
            // shared App Group cache; only fall through to a bare state when
            // there's nothing cached at all.
            if let cached = cachedContentState(forceStale: false) {
                return cached
            }
            return account == nil ? .notConnected : .needsAuth
        }

        let tokenProvider: @Sendable () async -> String? = { token }
        let projectRepository = clientFactory.makeProjectRepository(
            baseURL: account.baseURL, tokenProvider: tokenProvider,
        )
        let taskRepository = clientFactory.makeTaskRepository(
            baseURL: account.baseURL, tokenProvider: tokenProvider,
        )

        do {
            let projects = try await projectRepository.fetchProjects()
            let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            let tasks = await Self.fetchAllTasks(projects: projects, repository: taskRepository)

            let digest = TodayDigest(tasks: tasks, now: now())
            let content = TodayWidgetContent.make(
                digest: digest,
                projectsByID: projectsByID,
                accountName: account.displayName,
                now: now(),
                taskLimit: taskLimit,
            )
            cache.write(content)
            return .content(content)
        } catch VikunjaError.unauthorized {
            return .needsAuth
        } catch {
            return cachedContentState(forceStale: true) ?? .unavailable
        }
    }

    /// The last snapshot the widget or the app wrote to the shared cache.
    /// `forceStale` marks it stale unconditionally (a refresh was just
    /// attempted and failed); otherwise the badge only shows once the cache
    /// is meaningfully old.
    private func cachedContentState(forceStale: Bool) -> TodayWidgetState? {
        guard var cached = cache.read() else { return nil }
        let age = now().timeIntervalSince(cached.generatedAt)
        cached.isStale = forceStale || age > VikuWidgetConfig.refreshInterval * 2
        return .content(cached)
    }

    /// Fetches every project's tasks concurrently and flattens them; a project
    /// whose fetch fails is dropped rather than failing the whole refresh —
    /// mirrors `TodayViewModel.fetchAllTasks`.
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
            var all: [VikunjaTask] = []
            for await tasks in group {
                all.append(contentsOf: tasks)
            }
            return all
        }
    }
}
