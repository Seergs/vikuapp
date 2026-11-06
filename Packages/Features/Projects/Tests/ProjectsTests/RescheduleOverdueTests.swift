import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct RescheduleOverdueTests {
    private static let calendar = Calendar.current
    private static let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    private static let lastWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
    private static let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

    private func model(repository: FakeTaskRepository, toast: FakeToastPresenter) async -> ProjectOverviewViewModel {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Work")]
        let model = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            project: Project(id: 1, title: "Work"), repository: repository, bulkUpdateRepository: repository,
            projectRepository: projects, labelRepository: FakeLabelRepository(),
            relationRepository: FakeTaskRelationRepository(), filterRepository: FakeFilterRepository(),
            toastPresenter: toast, taskSortStore: FakeTaskSortStore(),
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

        let call = try #require(repository.dueDateCalls.first)
        #expect(repository.dueDateCalls.count == 1)
        #expect(call.ids == [1, 2])
        let parts = Self.calendar.dateComponents([.hour, .minute, .second], from: call.dueDate)
        #expect(parts.hour == 23 && parts.minute == 59 && parts.second == 59)
        #expect(model.tasks.map(\.dueDate) == [call.dueDate, call.dueDate, Self.yesterday])
        #expect(repository.updatedTasks.isEmpty)
        #expect(toast.shownMessages.map(\.style) == [.success])
    }

    @Test func `a failed local write keeps every due date and reports one error`() async {
        let repository = repository()
        repository.completionError = VikunjaError.notFound
        let toast = FakeToastPresenter()
        let model = await model(repository: repository, toast: toast)

        await model.rescheduleOverdue(model.tasks, to: .tomorrow)

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
}
