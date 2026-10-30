import Foundation
@testable import Kanban
import Testing
import VikunjaCore

@MainActor
struct KanbanLifecycleTests {
    private func model(
        _ repository: FakeBucketRepository,
        sync: TestScreenSync,
        toast: FakeToastPresenter = FakeToastPresenter(),
        haptics: FakeHapticPresenter = FakeHapticPresenter(),
    ) -> KanbanBoardViewModel {
        KanbanBoardViewModel(
            project: Project(id: 1, title: "Work"),
            repository: repository,
            syncTrigger: sync,
            localData: sync,
            toastPresenter: toast,
            hapticPresenter: haptics,
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    @Test func `online board capabilities allow movements while preventing ambiguous task creation`() async {
        let repository = FakeBucketRepository()
        repository.supportsTaskCreation = false
        repository.requiresConnection = true
        let task = VikunjaTask(id: 11, title: "Work task", projectID: 1)
        repository.buckets = [
            KanbanBucket(id: 10, title: "Todo", tasks: [task]),
            KanbanBucket(id: 20, title: "Done", isDoneBucket: true),
        ]
        let viewModel = model(repository, sync: TestScreenSync())
        await viewModel.load()
        #expect(viewModel.supportsWrites)
        #expect(!viewModel.supportsTaskCreation)
        #expect(viewModel.requiresConnection)
        await viewModel.createTask(title: "No owning project", in: repository.buckets[0])
        #expect(repository.createdTasks.isEmpty)
        await viewModel.toggleDone(task)
        #expect(repository.movedTaskIDs.first?.bucketID == 20)
    }

    @Test func `cached board is rendered before refresh and survives offline failure`() async {
        let repository = FakeBucketRepository()
        repository.buckets = [KanbanBucket(id: 1, title: "Cached")]
        let sync = TestScreenSync()
        let toast = FakeToastPresenter()
        let viewModel = model(repository, sync: sync, toast: toast)
        sync.onRefresh = {
            #expect(viewModel.hasSnapshot)
            #expect(viewModel.buckets.first?.title == "Cached")
            throw VikunjaError.offline
        }
        await viewModel.start()
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.buckets.first?.title == "Cached")
        #expect(sync.scopes == [.kanban(projectID: .remote(1))])
        #expect(toast.shownMessages.map(\.style) == [.info])
        sync.onRefresh = nil
    }

    @Test func `missing offline snapshot remains failed until refresh recovers with empty board`() async {
        let repository = FakeBucketRepository()
        repository.hasSnapshot = false
        let sync = TestScreenSync()
        sync.refreshError = .offline
        let viewModel = model(repository, sync: sync)
        await viewModel.start()
        #expect(!viewModel.hasSnapshot)
        #expect(viewModel.loadState.failureMessage != nil)
        await viewModel.load()
        #expect(viewModel.loadState.failureMessage != nil)
        sync.refreshError = nil
        sync.onRefresh = { repository.hasSnapshot = true }
        await viewModel.refresh()
        #expect(viewModel.hasSnapshot)
        #expect(viewModel.buckets.isEmpty)
        #expect(viewModel.loadState == .loaded)
    }

    @Test func `unsynced project waits and unsupported board rejects local writes`() async {
        let repository = FakeBucketRepository()
        repository.waitingForProject = true
        let sync = TestScreenSync()
        let viewModel = model(repository, sync: sync)
        await viewModel.start()
        #expect(viewModel.needsProjectSync)
        #expect(sync.scopes.isEmpty)
        repository.waitingForProject = false
        repository.supportsWrites = false
        repository.buckets = [KanbanBucket(id: 1, title: "Filtered")]
        await viewModel.load()
        #expect(!viewModel.needsProjectSync)
        #expect(viewModel.hasSnapshot)
        #expect(!viewModel.supportsWrites)
        await viewModel.createTask(title: "Blocked", in: repository.buckets[0])
        #expect(repository.createdTasks.isEmpty)
    }

    @Test func `observation reloads external changes cancels and resumes without duplicate subscriptions`() async {
        let repository = FakeBucketRepository()
        repository.buckets = [KanbanBucket(id: 1, title: "Initial")]
        let sync = TestScreenSync()
        let viewModel = model(repository, sync: sync)
        let first = Task { await viewModel.observeLocalChanges() }
        await waitUntil { sync.subscriptions == 1 && viewModel.hasSnapshot }
        let duplicate = Task { await viewModel.observeLocalChanges() }
        await duplicate.value
        #expect(sync.subscriptions == 1)
        repository.buckets[0].tasks = [VikunjaTask(id: .local(UUID()), title: "From quick add", projectID: 1)]
        sync.invalidate()
        await waitUntil { viewModel.buckets.first?.tasks.count == 1 }
        #expect(sync.scopes.isEmpty)
        first.cancel()
        await first.value
        await waitUntil { sync.terminations == 1 }
        let resumed = Task { await viewModel.observeLocalChanges() }
        await waitUntil { sync.subscriptions == 2 }
        repository.buckets[0].tasks = []
        sync.invalidate()
        await waitUntil { viewModel.buckets.first?.tasks.isEmpty == true }
        resumed.cancel()
        await resumed.value
    }

    @Test func `local identity moves and sync confirmation does not repeat haptics`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: .local(UUID()), title: "Offline", projectID: 1)
        repository.buckets = [
            KanbanBucket(id: 1, title: "Todo", tasks: [task]),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ]
        let haptics = FakeHapticPresenter()
        let viewModel = model(repository, sync: TestScreenSync(), haptics: haptics)
        await viewModel.load()
        await viewModel.toggleDone(task)
        #expect(repository.movedTaskIDs.first?.taskID == task.id)
        #expect(viewModel.buckets[1].tasks.first?.isDone == true)
        await viewModel.load()
        await viewModel.load()
        #expect(haptics.played == [.success])
        #expect(KanbanDragIdentity.decode(KanbanDragIdentity.encode(task.id)) == task.id)
        #expect(KanbanDragIdentity.decode("-1") == nil)
    }

    @Test func `empty non done columns can receive local tasks in both directions`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: .local(UUID()), title: "Offline card", projectID: 1)
        repository.buckets = [
            KanbanBucket(id: 1, title: "Todo", tasks: [task]),
            KanbanBucket(id: 2, title: "In progress"),
        ]
        let haptics = FakeHapticPresenter()
        let viewModel = model(repository, sync: TestScreenSync(), haptics: haptics)
        await viewModel.load()
        await viewModel.moveTask(taskID: task.id, to: viewModel.buckets[1])
        #expect(viewModel.buckets[0].tasks.isEmpty)
        #expect(viewModel.buckets[1].tasks.map(\.id) == [task.id])
        await viewModel.moveTask(taskID: task.id, to: viewModel.buckets[0])
        #expect(viewModel.buckets[1].tasks.isEmpty)
        #expect(viewModel.buckets[0].tasks.map(\.id) == [task.id])
        #expect(viewModel.buckets[0].tasks.first?.isDone == false)
        #expect(haptics.played.isEmpty)
    }

    @Test func `persistence failure does not produce completion feedback`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Task", projectID: 1)
        repository.buckets = [
            KanbanBucket(id: 1, title: "Todo", tasks: [task]),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ]
        repository.moveError = .notFound
        let haptics = FakeHapticPresenter()
        let toast = FakeToastPresenter()
        let viewModel = model(repository, sync: TestScreenSync(), toast: toast, haptics: haptics)
        await viewModel.load()
        await viewModel.toggleDone(task)
        #expect(haptics.played.isEmpty)
        #expect(viewModel.buckets[0].tasks.map(\.id) == [task.id])
        #expect(toast.shownMessages.count == 1)
    }
}
