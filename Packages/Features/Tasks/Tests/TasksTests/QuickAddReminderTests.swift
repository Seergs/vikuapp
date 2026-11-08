import Foundation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddReminderTests {
    private func makeModel(
        syntax: QuickAddSyntax? = .todoist,
        tasks: FakeTaskRepository = FakeTaskRepository(),
    ) throws -> QuickAddTaskViewModel {
        let zone = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 12,
        )))
        let model = QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: tasks,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            dateParsingContext: .init(referenceDate: reference, timeZone: zone, languages: [.spanish, .english]),
        )
        model.input = "Review"
        return model
    }

    private func relativeReminder(_ model: QuickAddTaskViewModel) -> TaskReminder {
        TaskReminder(reminder: model.dateParsingContext.referenceDate, relativePeriod: -1800, relativeTo: .dueDate)
    }

    @Test(arguments: [QuickAddSyntax?.none, .todoist, .vikunja])
    func `an absolute reminder can be saved without any due date`(syntax: QuickAddSyntax?) async throws {
        let tasks = FakeTaskRepository()
        let model = try makeModel(syntax: syntax, tasks: tasks)
        let absolute = TaskReminder(reminder: model.dateParsingContext.referenceDate.addingTimeInterval(86400))
        model.setReminder(absolute)
        #expect(model.reminder == absolute)
        #expect(tasks.tasks.isEmpty)
        let created = try #require(await model.save())
        #expect(created.dueDate == nil)
        #expect(created.reminders == [absolute])
    }

    @Test func `editing replaces the one reminder instead of adding another`() async throws {
        let model = try makeModel()
        model.pickDueDate(model.dateParsingContext.referenceDate.addingTimeInterval(86400))
        model.setReminder(relativeReminder(model))
        let absolute = TaskReminder(reminder: model.dateParsingContext.referenceDate.addingTimeInterval(7200))
        model.setReminder(absolute)
        #expect(model.reminder == absolute)
        let created = try #require(await model.save())
        #expect(created.reminders == [absolute])
    }

    @Test func `relative reminders require the due date anchor supported by the picker`() throws {
        let model = try makeModel()
        model.setReminder(relativeReminder(model))
        #expect(model.reminder == nil)
        model.pickDueDate(model.dateParsingContext.referenceDate)
        model.setReminder(TaskReminder(
            reminder: model.dateParsingContext.referenceDate, relativePeriod: -1800, relativeTo: .startDate,
        ))
        #expect(model.reminder == nil)
    }

    @Test func `picker date changes recalculate a relative reminder before saving`() async throws {
        let model = try makeModel()
        let initial = model.dateParsingContext.referenceDate.addingTimeInterval(86400)
        model.pickDueDate(initial)
        model.setReminder(relativeReminder(model))
        #expect(model.reminder?.reminder == initial.addingTimeInterval(-1800))
        let changed = initial.addingTimeInterval(86423)
        model.pickDueDate(changed)
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.reminder?.reminder == changed.addingTimeInterval(-1800))
        let created = try #require(await model.save())
        #expect(created.dueDate == changed)
        #expect(created.reminders.first?.reminder == changed.addingTimeInterval(-1800))
        #expect(created.reminders.first?.relativePeriod == -1800)
        #expect(created.reminders.first?.relativeTo == .dueDate)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `typed date changes and switching to the calendar keep the relative offset`(syntax: QuickAddSyntax) throws {
        let model = try makeModel(syntax: syntax)
        model.input = "Review tomorrow"
        model.setReminder(relativeReminder(model))
        model.input = "Review in a week"
        let typedDate = try #require(model.parsed.dueDate)
        #expect(model.input == "Review in a week")
        #expect(model.reminder?.reminder == typedDate.addingTimeInterval(-1800))
        #expect(!model.isConfirmingDueDateRemoval)
        let chosen = typedDate.addingTimeInterval(3600)
        model.pickDueDate(chosen)
        #expect(model.input == "Review")
        #expect(model.reminder?.reminder == chosen.addingTimeInterval(-1800))
        #expect(!model.isConfirmingDueDateRemoval)
        model.pickPriority(.high)
        #expect(model.reminder?.reminder == chosen.addingTimeInterval(-1800))
    }

    @Test func `removing a reminder immediately preserves the due date without confirmation`() async throws {
        let model = try makeModel()
        model.input = "Review tomorrow"
        let dueDate = try #require(model.dueDate)
        model.setReminder(relativeReminder(model))
        model.setReminder(nil)
        #expect(model.reminder == nil)
        #expect(model.dueDate == dueDate)
        #expect(model.input == "Review tomorrow")
        #expect(!model.isConfirmingDueDateRemoval)
        let created = try #require(await model.save())
        #expect(created.dueDate == dueDate)
        #expect(created.reminders.isEmpty)
    }

    @Test func `cancelling removal of a picked due date preserves both original values`() async throws {
        let tasks = FakeTaskRepository()
        let model = try makeModel(tasks: tasks)
        let dueDate = model.dateParsingContext.referenceDate.addingTimeInterval(86400)
        model.pickDueDate(dueDate)
        model.setReminder(relativeReminder(model))
        let reminder = model.reminder
        model.pickDueDate(nil)
        #expect(model.isConfirmingDueDateRemoval)
        #expect(model.dueDate == dueDate)
        #expect(model.reminder == reminder)
        #expect(!model.canSave)
        #expect(await model.save() == nil)
        #expect(tasks.tasks.isEmpty)
        model.cancelDueDateRemoval()
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.canSave)
        #expect(model.dueDate == dueDate)
        #expect(model.reminder == reminder)
        model.confirmDueDateRemoval()
        #expect(model.dueDate == dueDate)
    }

    @Test func `confirming picker removal clears both values and cleans only the date expression`() async throws {
        let model = try makeModel()
        model.input = "Review tomorrow p2"
        model.setReminder(relativeReminder(model))
        model.pickDueDate(nil)
        #expect(model.isConfirmingDueDateRemoval)
        #expect(model.input == "Review tomorrow p2")
        model.confirmDueDateRemoval()
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.dueDate == nil)
        #expect(model.reminder == nil)
        #expect(model.input == "Review p2")
        let created = try #require(await model.save())
        #expect(created.title == "Review")
        #expect(created.dueDate == nil)
        #expect(created.reminders.isEmpty)
    }

    @Test func `cancelling typed date removal restores the input due date and reminder`() throws {
        let model = try makeModel()
        model.input = "Review tomorrow"
        let dueDate = model.dueDate
        model.setReminder(relativeReminder(model))
        let reminder = model.reminder
        model.input = "Review"
        #expect(model.isConfirmingDueDateRemoval)
        #expect(model.input == "Review tomorrow")
        #expect(model.dueDate == dueDate)
        #expect(model.reminder == reminder)
        model.cancelDueDateRemoval()
        #expect(model.input == "Review tomorrow")
        #expect(model.dueDate == dueDate)
        #expect(model.reminder == reminder)
        #expect(model.canSave)
    }

    @Test func `confirming typed removal applies the requested edit and removes both linked values`() async throws {
        let model = try makeModel()
        model.input = "Review tomorrow"
        model.setReminder(relativeReminder(model))
        model.input = "Updated review"
        #expect(model.isConfirmingDueDateRemoval)
        #expect(model.input == "Review tomorrow")
        model.confirmDueDateRemoval()
        #expect(model.input == "Updated review")
        #expect(model.dueDate == nil)
        #expect(model.reminder == nil)
        let created = try #require(await model.save())
        #expect(created.title == "Updated review")
        #expect(created.dueDate == nil)
        #expect(created.reminders.isEmpty)
    }

    @Test func `an absolute reminder survives date changes and removal through either input or picker`() async throws {
        let model = try makeModel()
        let absolute = TaskReminder(reminder: model.dateParsingContext.referenceDate.addingTimeInterval(7200))
        model.setReminder(absolute)
        model.input = "Review tomorrow"
        #expect(model.reminder == absolute)
        model.input = "Review"
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.dueDate == nil)
        model.pickDueDate(model.dateParsingContext.referenceDate)
        model.pickDueDate(nil)
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.reminder == absolute)
        let created = try #require(await model.save())
        #expect(created.dueDate == nil)
        #expect(created.reminders == [absolute])
    }

    @Test func `a failed save keeps the linked reminder and due date for one successful retry`() async throws {
        let tasks = FakeTaskRepository()
        let model = try makeModel(tasks: tasks)
        model.pickDueDate(model.dateParsingContext.referenceDate.addingTimeInterval(86400))
        model.setReminder(relativeReminder(model))
        let reminder = model.reminder
        let dueDate = model.dueDate
        tasks.createError = .network("offline")
        #expect(await model.save() == nil)
        #expect(model.reminder == reminder)
        #expect(model.dueDate == dueDate)
        #expect(model.canSave)
        tasks.createError = nil
        let created = try #require(await model.save())
        #expect(try created.reminders == [#require(reminder)])
        #expect(created.dueDate == dueDate)
        #expect(tasks.tasks.count == 1)
    }

    @Test func `cancelled creation keeps the reminder draft for retry`() async throws {
        let tasks = FakeTaskRepository()
        tasks.beforeCreateReturns = { try Task.checkCancellation() }
        let model = try makeModel(tasks: tasks)
        let absolute = TaskReminder(reminder: model.dateParsingContext.referenceDate.addingTimeInterval(86400))
        model.setReminder(absolute)
        let operation = Task { await model.save() }
        operation.cancel()
        #expect(await operation.value == nil)
        #expect(model.reminder == absolute)
        #expect(tasks.tasks.isEmpty)
        tasks.beforeCreateReturns = nil
        let created = try #require(await model.save())
        #expect(created.reminders == [absolute])
        #expect(tasks.tasks.count == 1)
    }

    @Test func `removing the reminder cancels any pending linked date removal without removing the date`() throws {
        let model = try makeModel()
        model.input = "Review tomorrow"
        let date = model.dueDate
        model.setReminder(relativeReminder(model))
        model.pickDueDate(nil)
        #expect(model.isConfirmingDueDateRemoval)
        model.setReminder(nil)
        #expect(!model.isConfirmingDueDateRemoval)
        #expect(model.reminder == nil)
        #expect(model.dueDate == date)
        model.confirmDueDateRemoval()
        #expect(model.dueDate == date)
    }
}
