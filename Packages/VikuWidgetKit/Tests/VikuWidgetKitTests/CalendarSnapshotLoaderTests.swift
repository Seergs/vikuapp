import Foundation
import Testing
import VikunjaCore
import VikunjaPersistence
@testable import VikuWidgetKit

struct CalendarSnapshotLoaderTests {
    private static let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

    @Test func `renders local state without resolving a network token`() async {
        let account = TestSupport.account()
        let loader = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: account, token: nil),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot()), now: { Self.now },
        )
        guard case let .content(content) = await loader.loadState() else { Issue.record("Expected content"); return }
        #expect(content.todayTasks.map(\.id) == [10])
        #expect(content.accountID == account.id.uuidString)
        #expect(!content.isStale)
    }

    @Test func `failed sync retains local intent and marks saved content`() async {
        let loader = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: "token"),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot(
                lastPulledAt: Self.now.addingTimeInterval(-3600), pending: true,
            )),
            now: { Self.now }, synchronize: { _ in throw VikunjaError.network("offline") },
        )
        guard case let .content(content) = await loader.loadState() else {
            Issue.record("Expected saved content")
            return
        }
        #expect(content.todayTasks.map(\.id) == [10])
        #expect(content.isStale)
        #expect(content.hasPendingChanges)
    }

    @Test func `unauthorized sync preserves local content`() async {
        let loader = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: "old"),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot()), now: { Self.now },
            synchronize: { _ in throw VikunjaError.unauthorized },
        )
        guard case .content = await loader.loadState() else { Issue.record("Lost cached content"); return }
    }

    @Test func `missing local data reports auth failure or unavailable`() async {
        let store = FakeAccountStore(account: TestSupport.account(), token: "token")
        let empty = FakeLocalTaskSnapshotProvider(snapshot: nil)
        let auth = CalendarSnapshotLoader(
            accountStore: store,
            localSnapshotProvider: empty,
            synchronize: { _ in throw VikunjaError.unauthorized },
        )
        #expect(await auth.loadState() == .needsAuth)
        let offline = CalendarSnapshotLoader(
            accountStore: store,
            localSnapshotProvider: empty,
            synchronize: { _ in throw VikunjaError.offline },
        )
        #expect(await offline.loadState() == .unavailable)
        let disconnected = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: nil, token: nil), localSnapshotProvider: empty,
        )
        #expect(await disconnected.loadState() == .notConnected)
    }

    @Test func `interaction reload uses fresh local data without starting another sync`() async {
        let loader = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: "token"),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot(pending: true)),
            now: { Self.now }, synchronize: { _ in Issue.record("Fresh local reload waited for networking") },
        )
        guard case let .content(content) = await loader.loadState() else { Issue.record("Expected content"); return }
        #expect(content.todayTasks.map(\.id) == [10])
        #expect(content.hasPendingChanges)
    }

    @Test func `gallery reads never synchronize`() async {
        let loader = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: "token"),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot()), now: { Self.now },
            synchronize: { _ in Issue.record("Local preview attempted networking") },
        )
        #expect(await loader.loadLocalState() != nil)
    }

    @Test func `unknown download coverage is stale`() async {
        let loader = CalendarSnapshotLoader(
            accountStore: FakeAccountStore(account: TestSupport.account(), token: nil),
            localSnapshotProvider: FakeLocalTaskSnapshotProvider(snapshot: snapshot(lastPulledAt: nil)),
            now: { Self.now },
        )
        guard case let .content(content) = await loader.loadState() else { Issue.record("Expected content"); return }
        #expect(content.isStale)
    }

    private func snapshot(lastPulledAt: Date? = Self.now, pending: Bool = false) -> LocalTaskSnapshot {
        LocalTaskSnapshot(
            tasks: [VikunjaTask(id: 10, title: "Local", dueDate: Self.now, projectID: 1)],
            projects: [Project(id: 1, title: "Work")], lastPulledAt: lastPulledAt, hasPendingChanges: pending,
        )
    }
}
