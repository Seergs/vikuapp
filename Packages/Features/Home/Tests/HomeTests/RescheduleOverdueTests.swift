import Foundation
@testable import Home
import Testing
import VikunjaCore

@MainActor
struct RescheduleOverdueTests {
    private static let calendar = Calendar.current
    private static let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    private static let lastWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
    private static let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

    private func model(repository: FakeTaskRepository, toast: FakeToastPresenter) async -> TodayViewModel {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work")]
        let model = TodayViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            taskRepository: repository, bulkUpdateRepository: repository, projectRepository: projects,
            labelRepository: FakeLabelRepository(), relationRepository: FakeTaskRelationRepository(),
            toastPresenter: toast,
            homeSelectionCache: FakeHomeSelectionCaching(
                cached: CachedHomeSelection(id: 1, title: "Work", hexColor: "", kind: .project),
            ),
        )
        await model.load()
        return model
    }

    private func repository() -> FakeTaskRepository {
        let repository = FakeTaskRepository()
        repository.tasks = [
            VikunjaTask(id: 1, title: "Last week", dueDate: Self.lastWeek, projectID: 1),
            VikunjaTask(id: 2, title: "Yesterday", dueDate: Self.yesterday, projectID: 1),
            VikunjaTask(id: 3, title: "Hidden by search", dueDate: Self.yesterday, projectID: 1),
        ]
        return repository
    }

    @Test(arguments: [DueDateShortcut.today, .tomorrow])
    func `reschedules only the overdue tasks shown in one bulk write`(shortcut: DueDateShortcut) async throws {
        let repository = repository()
        let toast = FakeToastPresenter()
        let model = await model(repository: repository, toast: toast)

        await model.rescheduleOverdue(Array(model.tasks.prefix(2)), to: shortcut)

        #expect(repository.dueDateCalls.count == 1)
        let call = try #require(repository.dueDateCalls.first)
        #expect(call.ids == [1, 2])
        let parts = Self.calendar.dateComponents([.hour, .minute, .second], from: call.dueDate)
        #expect(parts.hour == 23 && parts.minute == 59 && parts.second == 59)
        #expect(model.tasks.map(\.dueDate) == [call.dueDate, call.dueDate, Self.yesterday])
        #expect(toast.shownMessages.map(\.style) == [.success])
        #expect(model.overdueRescheduler.completedCount == 1)
    }

    @Test func `a failed local write keeps every due date and reports one error`() async {
        let repository = repository()
        repository.completionError = VikunjaError.notFound
        let toast = FakeToastPresenter()
        let model = await model(repository: repository, toast: toast)

        await model.rescheduleOverdue(model.tasks, to: .today)

        #expect(model.tasks.map(\.dueDate) == [Self.lastWeek, Self.yesterday, Self.yesterday])
        #expect(toast.shownMessages.map(\.style) == [.error])
        #expect(!model.overdueRescheduler.isRescheduling)
    }

    @Test func `rescheduling is unavailable while selecting tasks`() async {
        let repository = repository()
        let model = await model(repository: repository, toast: FakeToastPresenter())
        model.bulkSelection.begin()

        await model.rescheduleOverdue(model.tasks, to: .today)

        #expect(repository.dueDateCalls.isEmpty)
    }

    @Test func `only the Overdue section offers its tasks for rescheduling`() {
        let tomorrow = Self.calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tasks = [
            VikunjaTask(id: 1, title: "Overdue", dueDate: Self.lastWeek, projectID: 1),
            VikunjaTask(id: 2, title: "Upcoming", dueDate: tomorrow, projectID: 1),
            VikunjaTask(id: 3, title: "Completed", isDone: true, projectID: 1),
        ]

        let digest = TodaySection.sections(from: tasks, filter: .all)
        #expect(digest.map { $0.overdueTasks?.map(\.id) } == [[1], nil])

        let pinned = PinnedTaskSection.sections(from: tasks)
        #expect(pinned.map { $0.overdueTasks?.map(\.id) } == [[1], nil, nil])
    }
}
