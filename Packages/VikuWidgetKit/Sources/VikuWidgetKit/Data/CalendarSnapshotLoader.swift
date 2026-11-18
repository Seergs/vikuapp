import Foundation
import VikunjaCore
import VikunjaPersistence

/// Builds the Calendar widget exclusively from the shared local database.
/// An optional bounded refresh merges server data through the normal sync
/// engine first; its raw responses never bypass pending local intent.
public struct CalendarSnapshotLoader: Sendable {
    private let accountStore: AccountStoreProtocol
    private let localSnapshotProvider: any WidgetLocalTaskSnapshotProviding
    private let taskLimit: Int
    private let now: @Sendable () -> Date
    private let synchronize: (@Sendable (UUID) async throws -> Void)?

    public init(
        accountStore: AccountStoreProtocol,
        localSnapshotProvider: any WidgetLocalTaskSnapshotProviding,
        taskLimit: Int = VikuWidgetConfig.calendarTaskLimit,
        now: @escaping @Sendable () -> Date = { Date() },
        synchronize: (@Sendable (UUID) async throws -> Void)? = nil,
    ) {
        self.accountStore = accountStore
        self.localSnapshotProvider = localSnapshotProvider
        self.taskLimit = taskLimit
        self.now = now
        self.synchronize = synchronize
    }

    public func loadState() async -> CalendarWidgetState {
        let account = try? await accountStore.activeAccount()
        if let snapshot = await localSnapshotProvider.loadSnapshot(accountID: account?.id),
           let lastPulledAt = snapshot.lastPulledAt, lastPulledAt <= now(),
           now().timeIntervalSince(lastPulledAt) < VikuWidgetConfig.refreshInterval {
            return contentState(snapshot: snapshot, account: account, forceStale: false)
        }
        var failed = false
        var needsAuth = account?.needsReauthentication == true
        if let account, let synchronize, !Task.isCancelled {
            do { try await synchronize(account.id) } catch {
                failed = !(error is CancellationError)
                if let error = error as? VikunjaError {
                    needsAuth = needsAuth || error == .unauthorized || error == .sessionExpired
                }
            }
        }
        if let local = await localContentState(account: account, forceStale: failed) {
            return local
        }
        if account == nil {
            return .notConnected
        }
        return needsAuth ? .needsAuth : .unavailable
    }

    /// No networking, including widget gallery previews and the app icon badge.
    public func loadLocalState() async -> CalendarWidgetState? {
        let account = try? await accountStore.activeAccount()
        return await localContentState(account: account, forceStale: false)
    }

    private func localContentState(account: InstanceAccount?, forceStale: Bool) async -> CalendarWidgetState? {
        guard let snapshot = await localSnapshotProvider.loadSnapshot(accountID: account?.id) else {
            return nil
        }
        return contentState(snapshot: snapshot, account: account, forceStale: forceStale)
    }

    private func contentState(
        snapshot: LocalTaskSnapshot, account: InstanceAccount?, forceStale: Bool,
    ) -> CalendarWidgetState {
        let projectsByID = Dictionary(
            uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) },
        )
        let month = CalendarMonth(containing: now(), tasks: snapshot.tasks, now: now())
        var content = CalendarWidgetContent.make(
            month: month,
            projectsByID: projectsByID,
            accountName: account?.displayName ?? "",
            accountID: account?.id.uuidString ?? "",
            now: now(),
            taskLimit: taskLimit,
        )
        let age = now().timeIntervalSince(snapshot.lastPulledAt ?? now())
        content.hasPendingChanges = snapshot.hasPendingChanges
        content.isStale = forceStale || snapshot.lastPulledAt == nil || age > VikuWidgetConfig.refreshInterval * 2
        return .content(content)
    }
}
