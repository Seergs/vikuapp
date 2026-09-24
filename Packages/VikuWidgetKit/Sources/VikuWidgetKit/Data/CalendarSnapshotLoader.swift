import Foundation
import VikunjaCore

/// Produces the calendar widget's `CalendarWidgetState` for one timeline
/// refresh: resolves the active account, pulls every project's tasks
/// concurrently (dropping a project whose fetch fails, exactly like
/// `TodaySnapshotLoader` and `CalendarViewModel`), lays them out on the current
/// month's grid via `CalendarMonth`, caches the result, and falls back to the
/// cached snapshot when the network fails.
///
/// Takes its dependencies as `VikunjaCore` protocols so it can be tested with
/// fakes; `VikuWidgetEnvironment` wires the real ones.
public struct CalendarSnapshotLoader: Sendable {
    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let cache: CalendarSnapshotCache
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
        cache: CalendarSnapshotCache,
        taskLimit: Int = VikuWidgetConfig.calendarTaskLimit,
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

    public func loadState() async -> CalendarWidgetState {
        let account = try? await accountStore.activeAccount()
        var token: String?
        if let account {
            // A `.sessionExpired` refresh failure has nothing more useful to
            // do here than fall back to the cache below — the widget can't
            // present a "sign in again" prompt of its own.
            token = try? await tokenResolver(account)
        }

        guard let account, let token, !token.isEmpty else {
            // The widget process can't reach the credentials (notably the iOS
            // Simulator). Render whatever the app last wrote to the shared
            // cache; only fall through to a bare state when nothing is cached.
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

            let month = CalendarMonth(containing: now(), tasks: tasks, now: now())
            let content = CalendarWidgetContent.make(
                month: month,
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
    /// is meaningfully old — same rule as `TodaySnapshotLoader`.
    private func cachedContentState(forceStale: Bool) -> CalendarWidgetState? {
        guard var cached = cache.read() else { return nil }
        let age = now().timeIntervalSince(cached.generatedAt)
        cached.isStale = forceStale || age > VikuWidgetConfig.refreshInterval * 2
        return .content(cached)
    }

    /// Fetches every project's tasks concurrently and flattens them; a project
    /// whose fetch fails is dropped rather than failing the whole refresh.
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
