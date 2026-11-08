import Foundation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddDueDateSelectionTests {
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
        return QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: tasks,
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            dateParsingContext: .init(referenceDate: reference, timeZone: zone, languages: [.spanish, .english]),
        )
    }

    private func pickedDate(_ model: QuickAddTaskViewModel) -> Date {
        // Fixed noon reference; preserve arbitrary seconds rather than round-trip through text.
        model.dateParsingContext.referenceDate.addingTimeInterval(8 * 86400 + 3600 + 23)
    }

    @Test(arguments: [QuickAddSyntax?.none, .todoist, .vikunja])
    func `picker works with either dialect or magic off and saves the exact date`(syntax: QuickAddSyntax?) async throws {
        let tasks = FakeTaskRepository()
        let model = try makeModel(syntax: syntax, tasks: tasks)
        model.input = "Review report"
        let chosen = pickedDate(model)
        model.pickDueDate(chosen)

        #expect(model.dueDate == chosen)
        #expect(model.input == "Review report")
        let created = try #require(await model.save())
        #expect(created.title == "Review report")
        #expect(created.dueDate == chosen)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `calendar replaces a typed date while preserving other shortcuts`(syntax: QuickAddSyntax) throws {
        let model = try makeModel(syntax: syntax)
        model.input = "Review tomorrow \(syntax.projectSigil)Work \(syntax.labelSigil)design"
        #expect(model.dueDate == model.parsed.dueDate)
        #expect(model.dueDate != nil)
        model.pickDueDate(pickedDate(model))

        #expect(model.input == "Review \(syntax.projectSigil)Work \(syntax.labelSigil)design")
        #expect(model.dueDate == pickedDate(model))
        #expect(model.parsed.dueDate == nil)
        #expect(!model.titleHighlights.spans.contains { $0.style == .date })
    }

    @Test(arguments: ["tomorrow Review report", "Review tomorrow report", "Review report tomorrow"])
    func `removing a typed date preserves the surrounding title`(input: String) async throws {
        let model = try makeModel()
        model.input = input
        #expect(model.dueDate != nil)
        model.pickDueDate(nil)
        #expect(model.input == "Review report")
        #expect(model.dueDate == nil)
        #expect(model.titleHighlights.spans.isEmpty)
        model.input += " updated"
        #expect(model.dueDate == nil)
        let created = try #require(await model.save())
        #expect(created.title == "Review report updated")
        #expect(created.dueDate == nil)
    }

    @Test func `a later typed date replaces a picker date and removing it clears the date`() throws {
        let model = try makeModel()
        model.input = "Review"
        model.pickDueDate(pickedDate(model))
        model.input = "Review tomorrow"
        let typed = try #require(model.parsed.dueDate)
        #expect(model.dueDate == typed)
        #expect(model.dueDate != pickedDate(model))
        #expect(model.titleHighlights.spans.contains { $0.style == .date })
        model.input = "Review next week"
        #expect(model.dueDate == model.parsed.dueDate)
        #expect(model.dueDate != typed)
        model.input = "Review"
        #expect(model.dueDate == nil)
    }

    @Test func `ordinary title project and priority edits preserve a picker date`() throws {
        let model = try makeModel()
        model.input = "Review"
        model.pickDueDate(pickedDate(model))
        model.input = "Review updated report"
        model.pickPriority(.high)
        model.pickProject(Project(id: 2, title: "tomorrow"))
        #expect(model.dueDate == pickedDate(model))
        #expect(model.parsed.dueDate == nil)
    }

    @Test func `removing a picker date leaves no date to save`() async throws {
        let model = try makeModel()
        model.input = "Review tomorrow"
        model.pickDueDate(pickedDate(model))
        model.pickDueDate(nil)
        #expect(model.dueDate == nil)
        #expect(model.input == "Review")
        #expect(try #require(await model.save()).dueDate == nil)
    }

    @Test func `picker preserves literal temporal words when magic is off`() async throws {
        let model = try makeModel(syntax: nil)
        model.input = "Review tomorrow"
        model.pickDueDate(pickedDate(model))
        #expect(model.input == "Review tomorrow")
        let created = try #require(await model.save())
        #expect(created.title == "Review tomorrow")
        #expect(created.dueDate == pickedDate(model))
    }

    @Test func `picker leaves ambiguous date phrases literal instead of deleting user text`() async throws {
        let model = try makeModel()
        model.input = "Review tomorrow or Friday"
        #expect(model.parsed.dueDate == nil)
        model.pickDueDate(pickedDate(model))
        #expect(model.input == "Review tomorrow or Friday")
        #expect(model.dueDate == pickedDate(model))
        let created = try #require(await model.save())
        #expect(created.title == "Review tomorrow or Friday")
        #expect(created.dueDate == pickedDate(model))
    }

    @Test func `a picker date alone does not supply a task title`() throws {
        let model = try makeModel()
        model.input = "tomorrow"
        model.pickDueDate(pickedDate(model))
        #expect(model.input.isEmpty)
        #expect(!model.canSave)
        model.input = "Review"
        #expect(model.canSave)
        #expect(model.dueDate == pickedDate(model))
    }

    @Test func `failed save keeps the chosen date for a successful retry`() async throws {
        let tasks = FakeTaskRepository()
        let model = try makeModel(tasks: tasks)
        model.input = "Review tomorrow"
        model.pickDueDate(pickedDate(model))
        tasks.createError = .network("offline")
        #expect(await model.save() == nil)
        #expect(model.input == "Review")
        #expect(model.dueDate == pickedDate(model))
        #expect(model.saveErrorMessage != nil)
        #expect(model.canSave)
        tasks.createError = nil
        let created = try #require(await model.save())
        #expect(created.dueDate == pickedDate(model))
        #expect(tasks.tasks.count == 1)
    }

    @Test func `cancelled save retains the picker date for retry`() async throws {
        let tasks = FakeTaskRepository()
        tasks.beforeCreateReturns = { try Task.checkCancellation() }
        let model = try makeModel(tasks: tasks)
        model.input = "Review"
        model.pickDueDate(pickedDate(model))
        let operation = Task { await model.save() }
        operation.cancel()
        #expect(await operation.value == nil)
        #expect(tasks.tasks.isEmpty)
        #expect(model.dueDate == pickedDate(model))
        #expect(model.canSave)
        tasks.beforeCreateReturns = nil
        let created = try #require(await model.save())
        #expect(created.dueDate == pickedDate(model))
    }
}
