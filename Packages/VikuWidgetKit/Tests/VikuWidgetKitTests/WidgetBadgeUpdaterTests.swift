import Foundation
import Testing
import VikunjaCore
import VikunjaPersistence
@testable import VikuWidgetKit

struct WidgetBadgeUpdaterTests {
    private static let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

    @Test func `badge and widget count only unfinished due tasks before applying the row limit`() async {
        let tasks = (1 ... 12).map { VikunjaTask(id: .remote($0), title: "Task", dueDate: Self.now, projectID: 1) }
            + [
                VikunjaTask(id: 20, title: "Done", isDone: true, dueDate: Self.now, projectID: 1),
                VikunjaTask(id: 21, title: "Overdue", dueDate: Self.now.addingTimeInterval(-86400), projectID: 1),
                VikunjaTask(
                    id: 22,
                    title: "Done overdue",
                    isDone: true,
                    dueDate: Self.now.addingTimeInterval(-86400),
                    projectID: 1,
                ),
                VikunjaTask(id: 23, title: "Future", dueDate: Self.now.addingTimeInterval(86400), projectID: 1),
            ]
        let snapshot = LocalTaskSnapshot(tasks: tasks, projects: [], lastPulledAt: Self.now)
        let writer = BadgeWrites()
        let updater = WidgetBadgeUpdater(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: nil),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot), isEnabled: { true },
            writeCount: { await writer.append($0) }, now: { Self.now },
        )
        await updater.refresh()
        #expect(await writer.counts == [13])
        let content = TodayWidgetContent.make(
            digest: TodayDigest(tasks: tasks, now: Self.now),
            projectsByID: [:],
            accountName: "Test",
            now: Self.now,
            taskLimit: 1,
        )
        #expect(content.tasks.count == 1)
        #expect(content.todayCount == 12)
        #expect(content.overdueCount == 1)
        #expect(content.pendingCount == 13)
        #expect(content.upcomingCount == 1)
    }

    @Test func `completed today stays available to reopen but no longer contributes to counts`() {
        let tasks = [
            VikunjaTask(id: 1, title: "Today", isDone: true, dueDate: Self.now, projectID: 1),
            VikunjaTask(
                id: 2,
                title: "Tomorrow",
                isDone: true,
                dueDate: Self.now.addingTimeInterval(86400),
                projectID: 1,
            ),
        ]
        let content = TodayWidgetContent.make(
            digest: TodayDigest(tasks: tasks, now: Self.now),
            projectsByID: [:],
            accountName: "Test",
            now: Self.now,
        )
        #expect(content.tasks.map(\.id) == [1, 2])
        let allCompleted = content.tasks.allSatisfy(\.isDone)
        #expect(allCompleted)
        #expect(content.pendingCount == 0)
        #expect(content.todayCount == 0)
        #expect(content.upcomingCount == 0)
    }

    @Test func `disabled badges clear while unavailable local data preserves the last enabled count`() async {
        let writer = BadgeWrites()
        let store = FakeAccountStore(account: TestSupport.account(), token: nil)
        let empty = FakeLocalTaskSnapshotProvider(snapshot: nil)
        let enabled = WidgetBadgeUpdater(
            accountStore: store,
            localSnapshotProvider: empty,
            isEnabled: { true },
            writeCount: { await writer.append($0) },
        )
        await enabled.refresh()
        #expect(await writer.counts.isEmpty)
        let disabled = WidgetBadgeUpdater(
            accountStore: store,
            localSnapshotProvider: empty,
            isEnabled: { false },
            writeCount: { await writer.append($0) },
        )
        await disabled.refresh()
        #expect(await writer.counts == [0])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a late snapshot cannot overwrite a newer badge refresh`() async {
        let started = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish() }
        let pending = LocalTaskSnapshot(
            tasks: [VikunjaTask(id: 1, title: "Task", dueDate: Self.now, projectID: 1)],
            projects: [], lastPulledAt: Self.now,
        )
        let completed = LocalTaskSnapshot(tasks: [], projects: [], lastPulledAt: Self.now)
        let snapshots = DelayedBadgeSnapshots(first: pending, next: completed, started: started.continuation)
        let writer = BadgeWrites()
        let updater = WidgetBadgeUpdater(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: nil),
            localSnapshotProvider: snapshots, isEnabled: { true },
            writeCount: { await writer.append($0) }, now: { Self.now },
        )
        let oldRefresh = Task { await updater.refresh() }
        var signals = started.stream.makeAsyncIterator()
        _ = await signals.next()
        await updater.refresh()
        await snapshots.release()
        await oldRefresh.value
        #expect(await writer.counts == [0])
    }

    @Test func `disabling the badge during a local read wins over the old count`() async {
        let suite = "viku.badge.test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preference = AppIconBadgePreference(suiteName: suite)
        preference.setEnabled(true)
        let snapshot = LocalTaskSnapshot(
            tasks: [VikunjaTask(id: 1, title: "Task", dueDate: Self.now, projectID: 1)],
            projects: [], lastPulledAt: Self.now,
        )
        let writer = BadgeWrites()
        let updater = WidgetBadgeUpdater(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: nil),
            localSnapshotProvider: ActionBadgeSnapshot {
                preference.setEnabled(false)
                return snapshot
            },
            isEnabled: { preference.isEnabled }, writeCount: { await writer.append($0) }, now: { Self.now },
        )
        await updater.refresh()
        #expect(await writer.counts == [0])
    }

    @Test func `badge preference is shared across independently constructed readers`() {
        let suite = "viku.badge.test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let app = AppIconBadgePreference(suiteName: suite)
        let widget = AppIconBadgePreference(suiteName: suite)
        #expect(!widget.isEnabled)
        app.setEnabled(true)
        #expect(widget.isEnabled)
        app.setEnabled(false)
        #expect(!widget.isEnabled)
    }
}

private actor BadgeWrites {
    private(set) var counts: [Int] = []
    func append(_ count: Int) {
        counts.append(count)
    }
}

private struct ActionBadgeSnapshot: WidgetLocalTaskSnapshotProviding {
    let action: @Sendable () async -> LocalTaskSnapshot?
    func loadSnapshot(accountID _: UUID?) async -> LocalTaskSnapshot? {
        await action()
    }
}

private actor DelayedBadgeSnapshots: WidgetLocalTaskSnapshotProviding {
    let first: LocalTaskSnapshot
    let next: LocalTaskSnapshot
    let started: AsyncStream<Void>.Continuation
    private var reads = 0
    private var waiter: CheckedContinuation<Void, Never>?

    init(first: LocalTaskSnapshot, next: LocalTaskSnapshot, started: AsyncStream<Void>.Continuation) {
        self.first = first
        self.next = next
        self.started = started
    }

    func loadSnapshot(accountID _: UUID?) async -> LocalTaskSnapshot? {
        reads += 1
        if reads == 1 {
            await withCheckedContinuation { continuation in
                waiter = continuation
                started.yield()
            }
            return first
        }
        return next
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}
