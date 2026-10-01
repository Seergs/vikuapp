@testable import Kanban
import Testing
import VikunjaCore

@MainActor
struct KanbanBoardViewModelTests {
    @Test
    func `load populates buckets from the repository`() async {
        let repository = FakeBucketRepository()
        repository.buckets = [
            KanbanBucket(id: 1, title: "To Do", tasks: [VikunjaTask(id: 1, title: "Write report", projectID: 4)]),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.buckets.map(\.title) == ["To Do", "Done"])
        #expect(viewModel.buckets[0].tasks.map(\.title) == ["Write report"])
    }

    @Test
    func `load surfaces a failure message when the repository throws`() async {
        let repository = FakeBucketRepository()
        repository.fetchError = .network("offline")
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )

        await viewModel.load()

        #expect(viewModel.loadState.failureMessage != nil)
    }

    @Test
    func `move task relocates it to the target bucket and persists through the repository`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 4)
        repository.buckets = [
            KanbanBucket(id: 1, title: "To Do", tasks: [task]),
            KanbanBucket(id: 2, title: "Doing"),
        ]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.moveTask(task, to: viewModel.buckets[1])

        #expect(viewModel.buckets[0].tasks.isEmpty)
        #expect(viewModel.buckets[1].tasks.map(\.id) == [1])
        #expect(repository.movedTaskIDs.map(\.bucketID) == [2])
    }

    @Test
    func `move task plays a success haptic only when landing in the done bucket`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 4)
        repository.buckets = [
            KanbanBucket(id: 1, title: "To Do", tasks: [task]),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ]
        let haptics = FakeHapticPresenter()
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
            hapticPresenter: haptics,
        )
        await viewModel.load()

        await viewModel.moveTask(task, to: viewModel.buckets[1])

        #expect(haptics.played == [.success])
    }

    @Test
    func `move task rolls back the board and shows a toast when the server rejects it`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 4)
        repository.buckets = [
            KanbanBucket(id: 1, title: "To Do", tasks: [task]),
            KanbanBucket(id: 2, title: "Doing"),
        ]
        repository.moveError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.moveTask(task, to: viewModel.buckets[1])

        #expect(viewModel.buckets[0].tasks.map(\.id) == [1])
        #expect(viewModel.buckets[1].tasks.isEmpty)
        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `move task is a no op when the task is already in the target bucket`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 4)
        repository.buckets = [KanbanBucket(id: 1, title: "To Do", tasks: [task])]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.moveTask(task, to: viewModel.buckets[0])

        #expect(repository.movedTaskIDs.isEmpty)
    }

    @Test
    func `create task in bucket posts through the repository and appends the server copy`() async {
        let repository = FakeBucketRepository()
        repository.buckets = [KanbanBucket(id: 1, title: "To Do")]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.createTask(title: "New card", in: viewModel.buckets[0])

        #expect(viewModel.buckets[0].tasks.map(\.title) == ["New card"])
        #expect(repository.createdTasks.map(\.bucketID) == [1])
    }

    @Test
    func `create task shows a toast and leaves the bucket unchanged when the server rejects it`() async {
        let repository = FakeBucketRepository()
        repository.buckets = [KanbanBucket(id: 1, title: "To Do")]
        repository.createError = .network("offline")
        let toastPresenter = FakeToastPresenter()
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: toastPresenter,
        )
        await viewModel.load()

        await viewModel.createTask(title: "New card", in: viewModel.buckets[0])

        #expect(viewModel.buckets[0].tasks.isEmpty)
        #expect(toastPresenter.shownMessages.map(\.style) == [.error])
    }

    @Test
    func `toggle done on a pending task moves it into the done bucket`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 4)
        repository.buckets = [
            KanbanBucket(id: 1, title: "To Do", tasks: [task]),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.toggleDone(task)

        #expect(viewModel.buckets[0].tasks.isEmpty)
        #expect(viewModel.buckets[1].tasks.map(\.id) == [1])
        #expect(repository.movedTaskIDs.map(\.bucketID) == [2])
    }

    @Test
    func `toggle done on a completed task moves it back to the first non done bucket`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Ship release", isDone: true, projectID: 4)
        repository.buckets = [
            KanbanBucket(id: 1, title: "To Do"),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true, tasks: [task]),
        ]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.toggleDone(task)

        #expect(viewModel.buckets[1].tasks.isEmpty)
        #expect(viewModel.buckets[0].tasks.map(\.id) == [1])
        #expect(repository.movedTaskIDs.map(\.bucketID) == [1])
    }

    @Test
    func `toggle done is a no op when the view has no done bucket`() async {
        let repository = FakeBucketRepository()
        let task = VikunjaTask(id: 1, title: "Write report", projectID: 4)
        repository.buckets = [KanbanBucket(id: 1, title: "To Do", tasks: [task])]
        let viewModel = KanbanBoardViewModel(
            project: Project(id: 4, title: "Work"),
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        await viewModel.load()

        await viewModel.toggleDone(task)

        #expect(repository.movedTaskIDs.isEmpty)
    }
}
