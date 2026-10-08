import Foundation
import Testing
import VikunjaCore
@testable import VikuWidgetKit

struct CalendarSnapshotLoaderTests {
    private static let calendar = Calendar.current
    /// Anchored to noon today rather than `Date()` directly: several cases
    /// below add a couple of hours to `now` to stay "later today", which
    /// would cross into tomorrow (and flip bucket) if the suite happened to
    /// run late at night.
    private static let now = calendar.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(),
    ) ?? Date()
    private static let laterToday = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
    private static let nextWeek = calendar.date(byAdding: .day, value: 5, to: now) ?? now

    private func makeLoader(
        account: InstanceAccount? = TestSupport.account(),
        token: String? = "secret",
        projects: [Project] = [],
        tasks: [VikunjaTask] = [],
        failingProjectIDs: Set<Int> = [],
        projectsError: VikunjaError? = nil,
        cacheDirectory: URL? = nil,
    ) -> (CalendarSnapshotLoader, CalendarSnapshotCache) {
        let store = FakeAccountStore(account: account, token: token)
        let projectRepo = FakeProjectRepository()
        projectRepo.projects = projects
        projectRepo.fetchError = projectsError
        let taskRepo = FakeTaskRepository()
        taskRepo.tasks = tasks
        taskRepo.failingProjectIDs = failingProjectIDs
        let cache = CalendarSnapshotCache(directory: cacheDirectory ?? TestSupport.tempCacheDirectory())
        let loader = CalendarSnapshotLoader(
            accountStore: store,
            clientFactory: FakeClientFactory(projectRepository: projectRepo, taskRepository: taskRepo),
            cache: cache,
            now: { Self.now },
        )
        return (loader, cache)
    }

    @Test
    func `reports not connected when there is no active account`() async {
        let (loader, _) = makeLoader(account: nil, token: nil)

        #expect(await loader.loadState() == .notConnected)
    }

    @Test
    func `lays every project's dated tasks onto the current month grid`() async {
        let projects = [
            Project(id: 1, title: "Work", hexColor: "#196AFF"),
            Project(id: 2, title: "Home", hexColor: "#1FA669"),
        ]
        let tasks = [
            VikunjaTask(id: 10, title: "Today A", dueDate: Self.laterToday, projectID: 1),
            VikunjaTask(id: 11, title: "Today B", dueDate: Self.laterToday, projectID: 2),
            VikunjaTask(id: 12, title: "Upcoming", dueDate: Self.nextWeek, projectID: 1),
            VikunjaTask(id: 13, title: "No due date", projectID: 2),
        ]
        let (loader, _) = makeLoader(projects: projects, tasks: tasks)

        guard case let .content(content) = await loader.loadState() else {
            Issue.record("expected content")
            return
        }
        let todayCell = content.weeks.flatMap(\.self).first { $0.isToday }
        #expect(todayCell?.dotColorHexes == ["#196AFF", "#1FA669"])
        #expect(content.todayTasks.map(\.id) == [10, 11])
        #expect(content.todayTaskCount == 2)
        #expect(content.isStale == false)
    }

    @Test
    func `ignores virtual projects so favorited tasks aren't counted twice`() async {
        let projects = [Project(id: 1, title: "Work"), Project(id: -1, title: "Favorites")]
        let tasks = [
            VikunjaTask(id: 10, title: "Real", dueDate: Self.laterToday, projectID: 1),
            VikunjaTask(id: 11, title: "Via favorites", dueDate: Self.laterToday, projectID: -1),
        ]
        let (loader, _) = makeLoader(projects: projects, tasks: tasks)

        guard case let .content(content) = await loader.loadState() else {
            Issue.record("expected content")
            return
        }
        #expect(content.todayTasks.map(\.id) == [10])
    }

    @Test
    func `one project's failing task fetch does not sink the snapshot`() async {
        let projects = [Project(id: 1, title: "Work"), Project(id: 2, title: "Home")]
        let tasks = [
            VikunjaTask(id: 10, title: "Kept", dueDate: Self.laterToday, projectID: 1),
            VikunjaTask(id: 11, title: "Lost", dueDate: Self.laterToday, projectID: 2),
        ]
        let (loader, _) = makeLoader(projects: projects, tasks: tasks, failingProjectIDs: [2])

        guard case let .content(content) = await loader.loadState() else {
            Issue.record("expected content")
            return
        }
        #expect(content.todayTasks.map(\.id) == [10])
    }

    @Test
    func `writes the snapshot to the cache on success`() async {
        let directory = TestSupport.tempCacheDirectory()
        let (loader, cache) = makeLoader(
            projects: [Project(id: 1, title: "Work")],
            tasks: [VikunjaTask(id: 10, title: "T", dueDate: Self.laterToday, projectID: 1)],
            cacheDirectory: directory,
        )

        _ = await loader.loadState()

        #expect(cache.read()?.todayTasks.map(\.id) == [10])
    }

    @Test
    func `falls back to a cached stale snapshot when the refresh fails`() async {
        let directory = TestSupport.tempCacheDirectory()
        let (goodLoader, _) = makeLoader(
            projects: [Project(id: 1, title: "Work")],
            tasks: [VikunjaTask(id: 10, title: "Cached", dueDate: Self.laterToday, projectID: 1)],
            cacheDirectory: directory,
        )
        _ = await goodLoader.loadState()

        let (failingLoader, _) = makeLoader(projectsError: .network("offline"), cacheDirectory: directory)

        guard case let .content(content) = await failingLoader.loadState() else {
            Issue.record("expected stale content")
            return
        }
        #expect(content.isStale)
        #expect(content.todayTasks.map(\.id) == [10])
    }

    @Test
    func `reports unavailable when the refresh fails and nothing is cached`() async {
        let (loader, _) = makeLoader(projectsError: .network("offline"))

        #expect(await loader.loadState() == .unavailable)
    }

    @Test
    func `reports needs auth when the server rejects the token`() async {
        let (loader, _) = makeLoader(projectsError: .unauthorized)

        #expect(await loader.loadState() == .needsAuth)
    }

    @Test
    func `renders the app written cache when the widget cannot reach credentials`() async {
        let directory = TestSupport.tempCacheDirectory()
        let (appLoader, _) = makeLoader(
            projects: [Project(id: 1, title: "Work")],
            tasks: [VikunjaTask(id: 10, title: "From the app", dueDate: Self.laterToday, projectID: 1)],
            cacheDirectory: directory,
        )
        _ = await appLoader.loadState()

        let (widgetLoader, _) = makeLoader(token: nil, cacheDirectory: directory)

        guard case let .content(content) = await widgetLoader.loadState() else {
            Issue.record("expected cached content")
            return
        }
        #expect(content.todayTasks.map(\.id) == [10])
        #expect(content.isStale == false)
    }
}
