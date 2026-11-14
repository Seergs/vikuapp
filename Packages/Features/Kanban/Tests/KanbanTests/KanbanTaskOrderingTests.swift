import Foundation
@testable import Kanban
import Testing
import VikunjaCore

@MainActor
struct KanbanTaskOrderingTests {
    @Test
    func `menu options use the full bucket and hide actions already satisfied`() async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let tasks = fixture.repository.buckets[0].tasks

        #expect(fixture.viewModel.orderingOptions(for: tasks[0])?.placements == [.bottom])
        #expect(fixture.viewModel.orderingOptions(for: tasks[1])?.placements == [.top, .bottom])
        #expect(fixture.viewModel.orderingOptions(for: tasks[2])?.placements == [.top])
        let options = try #require(fixture.viewModel.orderingOptions(for: tasks[1]))
        #expect(options.taskID == tasks[1].id && options.bucketID == 10 && options.viewID == 7)

        fixture.repository.buckets[0].tasks = [tasks[1]]
        await fixture.viewModel.load()
        #expect(fixture.viewModel.orderingOptions(for: tasks[1])?.placements.isEmpty == true)
        #expect(fixture.viewModel.orderingOptions(for: tasks[0]) == nil)
    }

    @Test(arguments: [KanbanTaskPlacement.top, .bottom])
    func `accepted ordering reloads cards without changing task fields or consuming capacity`(placement: KanbanTaskPlacement) async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let task = fixture.repository.buckets[0].tasks[1]
        let options = try #require(fixture.viewModel.orderingOptions(for: task))

        await fixture.viewModel.reorderTask(options, to: placement)

        let tasks = fixture.viewModel.buckets[0].tasks
        #expect(tasks.map(\.id) == (placement == .top ? [2, 1, 3] : [1, 3, 2]))
        #expect(tasks.first { $0.id == task.id } == task)
        #expect(fixture.viewModel.buckets[1].tasks.isEmpty)
        let request = try #require(fixture.repository.reorderedTasks.first)
        #expect(request.taskID == task.id && request.projectID == 4)
        #expect(request.viewID == 7 && request.bucketID == 10 && request.placement == placement)
        #expect(fixture.repository.movedTaskIDs.isEmpty)
        #expect(!fixture.viewModel.isReordering)
        #expect(fixture.toast.shownMessages.isEmpty)
    }

    @Test(arguments: [false, true])
    func `read only boards and missing ordering dependencies hide ordering`(hasDependency: Bool) async {
        let fixture = Fixture(hasDependency: hasDependency)
        fixture.repository.supportsWrites = !hasDependency
        await fixture.viewModel.load()
        #expect(fixture.viewModel.orderingOptions(for: fixture.repository.buckets[0].tasks[1]) == nil)
        #expect(fixture.repository.reorderedTasks.isEmpty)
    }

    @Test
    func `captured actions are rejected when the board becomes read only`() async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let options = try #require(fixture.viewModel.orderingOptions(for: fixture.repository.buckets[0].tasks[1]))
        fixture.repository.supportsWrites = false
        await fixture.viewModel.load()

        await fixture.viewModel.reorderTask(options, to: .top)

        #expect(fixture.repository.reorderedTasks.isEmpty)
        #expect(fixture.viewModel.buckets[0].tasks.map(\.id) == [1, 2, 3])
    }

    @Test
    func `captured actions cannot reorder a task that moved to another bucket or view`() async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let task = fixture.repository.buckets[0].tasks[1]
        let options = try #require(fixture.viewModel.orderingOptions(for: task))
        fixture.repository.buckets[0].tasks.remove(at: 1)
        fixture.repository.buckets[1].tasks = [task]
        await fixture.viewModel.load()

        await fixture.viewModel.reorderTask(options, to: .top)
        #expect(fixture.repository.reorderedTasks.isEmpty)

        fixture.repository.buckets[1].tasks = []
        fixture.repository.buckets[0].tasks.append(task)
        fixture.repository.viewID = 8
        await fixture.viewModel.load()
        await fixture.viewModel.reorderTask(options, to: .top)
        #expect(fixture.repository.reorderedTasks.isEmpty)
    }

    @Test
    func `pending acceptance blocks duplicate orders and dragging the same task`() async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let task = fixture.repository.buckets[0].tasks[1]
        let options = try #require(fixture.viewModel.orderingOptions(for: task))
        let destination = fixture.repository.buckets[1]
        fixture.repository.beforeReorder = {
            #expect(fixture.viewModel.isReordering)
            #expect(fixture.viewModel.orderingOptions(for: task) == nil)
            await Task.yield()
            await fixture.viewModel.reorderTask(options, to: .bottom)
            await fixture.viewModel.moveTask(task, to: destination)
        }

        await fixture.viewModel.reorderTask(options, to: .top)

        #expect(fixture.repository.reorderedTasks.count == 1)
        #expect(fixture.repository.movedTaskIDs.isEmpty)
        #expect(!fixture.viewModel.isReordering)
    }

    @Test(arguments: [VikunjaError.offline, .network("Rejected")])
    func `failed orders retain visible cards report feedback and permit retry`(error: VikunjaError) async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let task = fixture.repository.buckets[0].tasks[1]
        let options = try #require(fixture.viewModel.orderingOptions(for: task))
        fixture.repository.reorderError = error

        await fixture.viewModel.reorderTask(options, to: .top)

        #expect(fixture.viewModel.buckets[0].tasks.map(\.id) == [1, 2, 3])
        #expect(fixture.toast.shownMessages.count == 1)
        #expect(fixture.toast.shownMessages[0].style == (error == .offline ? .info : .error))
        #expect(!fixture.viewModel.isReordering)
        fixture.repository.reorderError = nil
        await fixture.viewModel.reorderTask(options, to: .top)
        #expect(fixture.viewModel.buckets[0].tasks.map(\.id) == [2, 1, 3])
    }

    @Test
    func `cancelled orders release busy state without error feedback`() async throws {
        let fixture = Fixture()
        await fixture.viewModel.load()
        let options = try #require(fixture.viewModel.orderingOptions(for: fixture.repository.buckets[0].tasks[1]))
        fixture.repository.reorderError = CancellationError()

        await fixture.viewModel.reorderTask(options, to: .top)

        #expect(fixture.viewModel.buckets[0].tasks.map(\.id) == [1, 2, 3])
        #expect(!fixture.viewModel.isReordering)
        #expect(fixture.toast.shownMessages.isEmpty)
    }

    @MainActor
    private struct Fixture {
        let repository = FakeBucketRepository()
        let toast = FakeToastPresenter()
        let viewModel: KanbanBoardViewModel

        init(hasDependency: Bool = true) {
            repository.buckets = [
                KanbanBucket(id: 10, title: "Full bucket", limit: 3, tasks: [
                    VikunjaTask(id: 1, title: "First", projectID: 4),
                    VikunjaTask(
                        id: 2,
                        title: "Middle",
                        isDone: true,
                        dueDate: Date(timeIntervalSince1970: 1_800_000_000),
                        priority: .urgent,
                        projectID: 4,
                    ),
                    VikunjaTask(id: 3, title: "Last", projectID: 4),
                ]),
                KanbanBucket(id: 20, title: "Other bucket"),
            ]
            self.viewModel = KanbanBoardViewModel(
                project: Project(id: 4, title: "Work"), repository: repository,
                orderingRepository: hasDependency ? repository : nil,
                syncTrigger: TestScreenSync(), localData: TestScreenSync(), toastPresenter: toast,
            )
        }
    }
}
