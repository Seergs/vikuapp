import Foundation
import Testing
import VikunjaCore
import VikunjaPersistence
@testable import VikuWidgetKit

struct WidgetTimelineReloadsTests {
    @Test(arguments: [VikuWidgetConfig.todayWidgetKind, VikuWidgetConfig.calendarWidgetKind])
    func `successful interaction explicitly reloads only the other kind`(source: String) async throws {
        let requests = ReloadKindRequests()
        let reloads = WidgetTimelineReloads { await requests.append($0) }
        try await reloads.duringInteraction(sourceKind: source) {
            await reloads.request()
            await reloads.request()
        }
        let otherKinds: Set<String> = [VikuWidgetConfig.todayWidgetKind, VikuWidgetConfig.calendarWidgetKind]
        #expect(await requests.values == [otherKinds.subtracting([source])])
        await reloads.request()
        #expect(await requests.values == [otherKinds.subtracting([source]), otherKinds])
    }

    @Test(arguments: [VikuWidgetConfig.todayWidgetKind, VikuWidgetConfig.calendarWidgetKind])
    func `overlap with another kind cannot leave an earlier source stale`(secondSource: String) async throws {
        let requests = ReloadKindRequests()
        let reloads = WidgetTimelineReloads { await requests.append($0) }
        try await reloads.duringInteraction(sourceKind: VikuWidgetConfig.todayWidgetKind) {
            try await reloads.duringInteraction(sourceKind: secondSource) {
                await reloads.request()
            }
            await reloads.request()
        }
        let expected: Set<String> = secondSource == VikuWidgetConfig.todayWidgetKind
            ? [VikuWidgetConfig.calendarWidgetKind]
            : [VikuWidgetConfig.todayWidgetKind, VikuWidgetConfig.calendarWidgetKind]
        #expect(await requests.values == [expected])
    }

    @Test func `failed intent refreshes accepted state without relying on an automatic source reload`() async {
        let requests = ReloadKindRequests()
        let reloads = WidgetTimelineReloads { await requests.append($0) }
        await #expect(throws: CancellationError.self) {
            try await reloads.duringInteraction(sourceKind: VikuWidgetConfig.todayWidgetKind) {
                await reloads.request()
                throw CancellationError()
            }
        }
        #expect(await requests.values == [[VikuWidgetConfig.todayWidgetKind, VikuWidgetConfig.calendarWidgetKind]])
    }

    @Test func `rejected interaction does not affect the next successful source`() async throws {
        let requests = ReloadKindRequests()
        let reloads = WidgetTimelineReloads { await requests.append($0) }
        await #expect(throws: VikunjaError.self) {
            try await reloads.duringInteraction(sourceKind: VikuWidgetConfig.todayWidgetKind) {
                throw VikunjaError.notFound
            }
        }
        try await reloads.duringInteraction(sourceKind: VikuWidgetConfig.calendarWidgetKind) {
            await reloads.request()
        }
        #expect(await requests.values == [[VikuWidgetConfig.todayWidgetKind]])
    }

    @Test func `local acceptance and sync completion issue one cross-widget request`() async throws {
        let events = ReloadEvents()
        let reloads = WidgetTimelineReloads { _ in await events.append("reload") }
        try await reloads.duringInteraction {
            await events.append("local")
            await reloads.request()
            #expect(await events.values == ["local"])
            await events.append("uploaded")
            await reloads.request()
        }
        #expect(await events.values == ["local", "uploaded", "reload"])
    }

    @Test func `overlapping interactions flush only when the last interaction finishes`() async throws {
        let events = ReloadEvents()
        let reloads = WidgetTimelineReloads { _ in await events.append("reload") }
        try await reloads.duringInteraction {
            await reloads.request()
            try await reloads.duringInteraction { await reloads.request() }
            #expect(await events.values.isEmpty)
        }
        #expect(await events.values == ["reload"])
    }

    @Test func `cancellation flushes accepted changes and does not leave batching stuck`() async {
        let events = ReloadEvents()
        let reloads = WidgetTimelineReloads { _ in await events.append("reload") }
        let work = Task {
            try await reloads.duringInteraction {
                await reloads.request()
                withUnsafeCurrentTask { $0?.cancel() }
                try Task.checkCancellation()
            }
        }
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(await events.values == ["reload"])
        await reloads.request()
        #expect(await events.values == ["reload", "reload"])
    }

    @Test func `rejected local writes do not request unrelated widget reloads`() async {
        let events = ReloadEvents()
        let reloads = WidgetTimelineReloads { _ in await events.append("reload") }
        await #expect(throws: VikunjaError.self) {
            try await reloads.duringInteraction { throw VikunjaError.notFound }
        }
        #expect(await events.values.isEmpty)
        await reloads.request()
        #expect(await events.values == ["reload"])
    }

    @Test func `both widget readers and the small counter reflect completing and reopening`() async throws {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let account = TestSupport.account()
        let tasks = SharedWidgetTasks(now: now)
        let accounts = FakeAccountStore(account: account, token: nil)
        let today = TodaySnapshotLoader(accountStore: accounts, localSnapshotProvider: tasks, now: { now })
        let calendar = CalendarSnapshotLoader(accountStore: accounts, localSnapshotProvider: tasks, now: { now })
        let completion = WidgetTaskCompletion(repository: tasks, synchronize: {}, reload: {})
        for isDone in [true, false, true, false] {
            try await completion.setCompletion(taskID: 10, isDone: isDone)
            guard case let .content(todayContent) = await today.loadState(),
                  case let .content(calendarContent) = await calendar.loadState() else {
                Issue.record("Both widget readers must return local content")
                return
            }
            #expect(todayContent.todayCount == (isDone ? 0 : 1))
            #expect(todayContent.pendingCount == (isDone ? 0 : 1))
            #expect(todayContent.tasks.first?.isDone == isDone)
            #expect(calendarContent.todayTasks.first?.isDone == isDone)
        }
    }
}

private actor ReloadEvents {
    private(set) var values: [String] = []
    func append(_ value: String) {
        values.append(value)
    }
}

private actor ReloadKindRequests {
    private(set) var values: [Set<String>] = []
    func append(_ kinds: Set<String>) {
        values.append(kinds)
    }
}

private actor SharedWidgetTasks: TaskBulkUpdateRepositoryProtocol, WidgetLocalTaskSnapshotProviding {
    let now: Date
    private var isDone = false
    init(now: Date) {
        self.now = now
    }

    func apply(_ change: TaskBulkChange, toTaskIDs _: [EntityID]) -> [VikunjaTask] {
        if case let .completion(value) = change {
            isDone = value
        }
        return []
    }

    func loadSnapshot(accountID _: UUID?) -> LocalTaskSnapshot? {
        LocalTaskSnapshot(
            tasks: [VikunjaTask(id: 10, title: "Task", isDone: isDone, dueDate: now, projectID: 1)],
            projects: [Project(id: 1, title: "Project")], lastPulledAt: now,
        )
    }
}
