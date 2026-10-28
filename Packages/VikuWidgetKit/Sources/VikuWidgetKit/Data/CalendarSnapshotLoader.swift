import Foundation
import VikunjaCore

/// Produces the calendar widget's `CalendarWidgetState` for one timeline
/// refresh: resolves the active account, pulls every project's tasks
/// concurrently (dropping a project whose fetch fails, exactly like
/// `TodaySnapshotLoader` and `CalendarViewModel`), lays them out on the current
/// month's grid via `CalendarMonth`, and falls back to the app's shared offline
/// database when the network or credentials are unavailable.
///
/// Takes its dependencies as `VikunjaCore` protocols so it can be tested with
/// fakes; `VikuWidgetEnvironment` wires the real ones.
public struct CalendarSnapshotLoader: Sendable {
    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let localSnapshotProvider: any WidgetLocalTaskSnapshotProviding
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
        localSnapshotProvider: any WidgetLocalTaskSnapshotProviding,
        taskLimit: Int = VikuWidgetConfig.calendarTaskLimit,
        now: @escaping @Sendable () -> Date = { Date() },
        tokenResolver: (@Sendable (InstanceAccount) async throws -> String?)? = nil,
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.localSnapshotProvider = localSnapshotProvider
        self.taskLimit = taskLimit
        self.now = now
        self.tokenResolver = tokenResolver ?? { try? await accountStore.token(forAccountID: $0.id) }
    }

    public func loadState() async -> CalendarWidgetState {
        let account = try? await accountStore.activeAccount()
        var token: String?
        if let account {
            // A `.sessionExpired` refresh failure has nothing more useful to
            // do here than fall back to the local store below — the widget
            // can't present a "sign in again" prompt of its own.
            token = try? await tokenResolver(account)
        }

        guard let account, let token, !token.isEmpty else {
            // The widget process can't reach the credentials (notably the iOS
            // Simulator). Render whatever the app last synced into the shared
            // offline database; only fall through to a bare state when there's
            // nothing stored at all.
            if let local = await localContentState(account: account, forceStale: false) {
                return local
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
            let (tasks, projectsByID) = try await AccountTaskLoader(
                taskRepository: taskRepository,
                projectRepository: projectRepository,
            ).loadAllTasks()

            let month = CalendarMonth(containing: now(), tasks: tasks, now: now())
            let content = CalendarWidgetContent.make(
                month: month,
                projectsByID: projectsByID,
                accountName: account.displayName,
                now: now(),
                taskLimit: taskLimit,
            )
            return .content(content)
        } catch VikunjaError.unauthorized {
            return .needsAuth
        } catch {
            return await localContentState(account: account, forceStale: true) ?? .unavailable
        }
    }

    /// The app's last synced tasks and projects for this account. `forceStale`
    /// marks the fallback stale unconditionally (a refresh was just attempted
    /// and failed); otherwise the badge only shows once the local data is
    /// meaningfully old — same rule as `TodaySnapshotLoader`.
    private func localContentState(account: InstanceAccount?, forceStale: Bool) async -> CalendarWidgetState? {
        guard let snapshot = await localSnapshotProvider.loadSnapshot(accountID: account?.id) else {
            return nil
        }
        let projectsByID = Dictionary(
            uniqueKeysWithValues: snapshot.projects.compactMap { project in
                project.id.remoteValue.map { ($0, project) }
            },
        )
        let month = CalendarMonth(containing: now(), tasks: snapshot.tasks, now: now())
        var content = CalendarWidgetContent.make(
            month: month,
            projectsByID: projectsByID,
            accountName: account?.displayName ?? "",
            now: now(),
            taskLimit: taskLimit,
        )
        let age = now().timeIntervalSince(snapshot.lastPulledAt ?? now())
        content.isStale = forceStale || age > VikuWidgetConfig.refreshInterval * 2
        return .content(content)
    }
}
