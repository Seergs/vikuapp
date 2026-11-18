import Foundation
import VikunjaCore

/// Computes badges from all local tasks, never a capped widget row list or a
/// remote read. The writer is injected so count and preference races are tested
/// without changing the host machine's real notification badge.
public actor WidgetBadgeUpdater {
    private let accountStore: any AccountStoreProtocol
    private let localSnapshotProvider: any WidgetLocalTaskSnapshotProviding
    private let isEnabled: @Sendable () -> Bool
    private let writeCount: @Sendable (Int) async throws -> Void
    private let now: @Sendable () -> Date
    private var revision = 0

    public init(
        accountStore: any AccountStoreProtocol,
        localSnapshotProvider: any WidgetLocalTaskSnapshotProviding,
        isEnabled: @escaping @Sendable () -> Bool,
        writeCount: @escaping @Sendable (Int) async throws -> Void,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.accountStore = accountStore
        self.localSnapshotProvider = localSnapshotProvider
        self.isEnabled = isEnabled
        self.writeCount = writeCount
        self.now = now
    }

    public func refresh() async {
        revision += 1
        let requestRevision = revision
        guard isEnabled() else { try? await writeCount(0); return }
        guard let account = try? await accountStore.activeAccount(),
              let snapshot = await localSnapshotProvider.loadSnapshot(accountID: account.id),
              let current = try? await accountStore.activeAccount(), current.id == account.id else { return }
        guard requestRevision == revision else { return }
        let content = TodayWidgetContent.make(
            digest: TodayDigest(tasks: snapshot.tasks, now: now()),
            projectsByID: [:], accountName: account.displayName, now: now(),
        )
        try? await writeCount(isEnabled() ? content.pendingCount : 0)
    }
}
