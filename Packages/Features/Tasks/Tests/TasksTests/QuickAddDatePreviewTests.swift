import Foundation
import Observation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddDatePreviewTests {
    private typealias Parser = NaturalLanguageDateParser

    private func context(zone: String = "UTC") throws -> Parser.Context {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 12,
        )))
        return try Parser.Context(
            referenceDate: reference,
            timeZone: #require(TimeZone(identifier: zone)),
            languages: [.spanish, .english],
        )
    }

    private func viewModel(
        syntax: QuickAddSyntax? = .todoist,
        tasks: FakeTaskRepository = FakeTaskRepository(),
        projects: FakeProjectRepository = FakeProjectRepository(),
        context suppliedContext: Parser.Context? = nil,
        datePreviewStore: QuickAddDatePreviewStoring? = nil,
    ) throws -> QuickAddTaskViewModel {
        try QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: tasks,
            projectRepository: projects,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            datePreviewStore: datePreviewStore,
            dateParsingContext: suppliedContext ?? context(),
        )
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `saving applies the interpreted date without mutating raw input`(_ syntax: QuickAddSyntax) async throws {
        let tasks = FakeTaskRepository()
        let model = try viewModel(syntax: syntax, tasks: tasks)
        model.input = "Comprar leche mañana a las 18:30"
        let preview = try #require(model.datePreview.resolvedDate)
        #expect(preview.components.day == 6)
        #expect(preview.components.hour == 18)
        #expect(model.parsed.title == "Comprar leche")
        #expect(model.canSave)
        let saved = try #require(await model.save())
        #expect(saved.title == "Comprar leche")
        #expect(saved.dueDate == preview.date)
        #expect(model.input == "Comprar leche mañana a las 18:30")
        #expect(tasks.tasks.count == 1)
    }

    @Test func `preview does not change existing shortcut behavior`() async throws {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Compras")]
        let model = try viewModel(projects: projects)
        await model.load()
        model.input = "Leche mañana #Compras p1"
        #expect(model.datePreview.status == .resolved)
        #expect(model.selectedProjectID == 1)
        #expect(model.priority == .urgent)
        let saved = try #require(await model.save())
        #expect(saved.title == "Leche")
        #expect(saved.priority == .urgent)
        #expect(saved.dueDate == model.datePreview.resolvedDate?.date)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `protects shortcut names before projects or labels load`(_ syntax: QuickAddSyntax) throws {
        let model = try viewModel(syntax: syntax)
        model.input = syntax == .todoist ?
            "Leche #\"mañana\" @tomorrow next Saturday" : "Leche +\"mañana\" *tomorrow next Saturday"
        #expect(model.datePreview.expressions.map(\.text) == ["next Saturday"])
        #expect(model.datePreview.status == .resolved)
    }

    @Test func `disabling magic disables preview`() async throws {
        let model = try viewModel(syntax: nil)
        model.input = "Leche mañana #Compras"
        #expect(!model.isDatePreviewEnabled)
        #expect(model.datePreview.status == .noMatch)
        let saved = try #require(await model.save())
        #expect(saved.title == model.input)
        #expect(saved.dueDate == nil)
    }

    @Test func `preview works offline and survives save failure`() async throws {
        let tasks = FakeTaskRepository()
        tasks.createError = .network("offline")
        let projects = FakeProjectRepository()
        projects.fetchError = .network("offline")
        let model = try viewModel(tasks: tasks, projects: projects)
        model.input = "Leche mañana"
        let before = model.datePreview
        await model.load()
        #expect(model.datePreview == before)
        #expect(model.datePreview.status == .resolved)
        #expect(await model.save() == nil)
        #expect(model.input == "Leche mañana")
        #expect(model.datePreview == before)
        #expect(model.saveErrorMessage != nil)
        tasks.createError = nil
        let retried = try #require(await model.save())
        #expect(retried.title == "Leche")
        #expect(retried.dueDate == before.resolvedDate?.date)
    }

    @Test(arguments: ["hoy o mañana", "31 de febrero", "cada lunes", "en tres"])
    func `diagnostics never block saving literal title`(_ text: String) async throws {
        let model = try viewModel()
        model.input = text
        #expect(model.datePreview.resolvedDate == nil)
        #expect(!model.datePreview.expressions.isEmpty)
        #expect(model.canSave)
        let saved = try #require(await model.save())
        #expect(saved.title == text)
        #expect(saved.dueDate == nil)
    }

    @Test func `input edits update preview and preserve reference`() throws {
        let model = try viewModel()
        model.input = "Leche mañana"
        let first = model.datePreview.resolvedDate
        model.input = "Comprar leche mañana"
        #expect(model.datePreview.resolvedDate == first)
        model.input = "Comprar leche en dos meses"
        #expect(model.datePreview.resolvedDate?.components.month == 1)
        #expect(model.datePreview.resolvedDate?.components.year == 2027)
        model.input = "Comprar leche"
        #expect(model.datePreview.status == .noMatch)
        model.input = ""
        #expect(model.datePreview.status == .noMatch)
        #expect(!model.canSave)
    }

    @Test func `formats resolution in the explicitly supplied zone`() throws {
        let model = try viewModel(context: context(zone: "Asia/Tokyo"))
        model.input = "tomorrow"
        let result = try #require(model.datePreview.resolvedDate)
        #expect(result.timeZoneIdentifier == "Asia/Tokyo")
        #expect(result.components.hour == 23)
        #expect(result.components.minute == 59)
        #expect(result.components.second == 59)
        #expect(model.dateParsingContext.timeZone.identifier == "Asia/Tokyo")
    }

    @Test func `device local end of day matches preview and saved due date`() async throws {
        let model = try viewModel(context: context(zone: "America/Mexico_City"))
        model.input = "Comprar leche hoy"
        let preview = try #require(model.datePreview.resolvedDate)
        let saved = try #require(await model.save())
        #expect(saved.title == "Comprar leche")
        #expect(saved.dueDate == preview.date)
        #expect(preview.timeZoneIdentifier == "America/Mexico_City")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.dateParsingContext.timeZone
        let components = try calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: #require(saved.dueDate),
        )
        #expect(components == DateComponents(year: 2026, month: 11, day: 5, hour: 23, minute: 59, second: 59))
    }

    @Test func `default context captures the device zone`() {
        let model = QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: .todoist),
        )
        #expect(model.dateParsingContext.timeZone == TimeZone.current)
        model.input = "Comprar leche hoy"
        #expect(model.datePreview.resolvedDate?.timeZoneIdentifier == model.dateParsingContext.timeZone.identifier)
    }

    @Test func `attached meridiem is applied when saving`() async throws {
        let model = try viewModel()
        model.input = "Leche mañana a las 6pm"
        let result = try #require(model.datePreview.resolvedDate)
        #expect(result.components.hour == 18)
        #expect(result.components.minute == 0)
        let saved = try #require(await model.save())
        #expect(saved.title == "Leche")
        #expect(saved.dueDate == result.date)
    }

    @Test func `zone selection changes interpretation without changing parser rules`() throws {
        let gmt = try viewModel(context: context(zone: "GMT"))
        let mexico = try viewModel(context: context(zone: "America/Mexico_City"))
        gmt.input = "hoy"
        mexico.input = "hoy"
        let gmtDate = try #require(gmt.datePreview.resolvedDate)
        let mexicoDate = try #require(mexico.datePreview.resolvedDate)
        #expect(gmtDate.components.hour == 23)
        #expect(mexicoDate.components.hour == 23)
        #expect(mexicoDate.date.timeIntervalSince(gmtDate.date) == 6 * 3600)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mexico.dateParsingContext.timeZone
        let gmtInMexico = calendar.dateComponents([.hour, .minute, .second], from: gmtDate.date)
        #expect(gmtInMexico == DateComponents(hour: 17, minute: 59, second: 59))
    }

    @Test func `dates apply even when the developer panel is hidden`() async throws {
        let model = try viewModel()
        model.input = "Leche mañana"
        #expect(!model.isDatePreviewEnabled)
        #expect(model.datePreview.status == .resolved)
        let saved = try #require(await model.save())
        #expect(saved.title == "Leche")
        #expect(saved.dueDate == model.datePreview.resolvedDate?.date)
    }

    @Test func `session toggle controls existing model without changing interpretation`() throws {
        let store = FakeDatePreviewStore()
        let model = try viewModel(datePreviewStore: store)
        model.input = "Leche mañana"
        let interpretation = model.datePreview
        #expect(!model.isDatePreviewEnabled)
        store.setQuickAddDatePreviewVisible(true)
        #expect(model.isDatePreviewEnabled)
        let reopened = try viewModel(datePreviewStore: store)
        #expect(reopened.isDatePreviewEnabled)
        #expect(model.datePreview == interpretation)
        store.setQuickAddDatePreviewVisible(false)
        #expect(!model.isDatePreviewEnabled)
        #expect(!reopened.isDatePreviewEnabled)
        #expect(model.datePreview == interpretation)
        #expect(model.input == "Leche mañana")
    }

    @Test func `developer toggle does not override disabled magic`() throws {
        let store = FakeDatePreviewStore()
        store.setQuickAddDatePreviewVisible(true)
        let model = try viewModel(syntax: nil, datePreviewStore: store)
        model.input = "Leche mañana"
        #expect(!model.isDatePreviewEnabled)
        #expect(model.datePreview.status == .noMatch)
    }

    @Test(arguments: ["mañana", "tomorrow at 6pm", "2027-11-15", "mañana #Compras p1"])
    func `recognized date cannot leave an empty task title`(_ input: String) async throws {
        let tasks = FakeTaskRepository()
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 1, title: "Compras")]
        let model = try viewModel(tasks: tasks, projects: projects)
        await model.load()
        model.input = input
        #expect(model.datePreview.resolvedDate != nil)
        #expect(model.parsed.title.isEmpty)
        #expect(!model.canSave)
        #expect(await model.save() == nil)
        #expect(tasks.tasks.isEmpty)
        #expect(model.input == input)
    }

    @Test func `adding title after date only input enables saving`() async throws {
        let model = try viewModel()
        model.input = "mañana"
        #expect(!model.canSave)
        let date = try #require(model.datePreview.resolvedDate?.date)
        model.input = "Comprar leche mañana"
        #expect(model.canSave)
        let saved = try #require(await model.save())
        #expect(saved.title == "Comprar leche")
        #expect(saved.dueDate == date)
    }

    @Test func `cancelled save retains original text and resolved date for retry`() async throws {
        let tasks = FakeTaskRepository()
        tasks.beforeCreateReturns = { try Task.checkCancellation() }
        let model = try viewModel(tasks: tasks)
        model.input = "Leche mañana"
        let date = try #require(model.datePreview.resolvedDate?.date)
        let operation = Task { await model.save() }
        operation.cancel()
        #expect(await operation.value == nil)
        #expect(tasks.tasks.isEmpty)
        #expect(model.input == "Leche mañana")
        #expect(model.parsed.dueDate == date)
        #expect(model.canSave)
        tasks.beforeCreateReturns = nil
        let retried = try #require(await model.save())
        #expect(retried.title == "Leche")
        #expect(retried.dueDate == date)
    }
}

@MainActor
@Observable
private final class FakeDatePreviewStore: QuickAddDatePreviewStoring {
    var isQuickAddDatePreviewVisible = false

    func setQuickAddDatePreviewVisible(_ visible: Bool) {
        isQuickAddDatePreviewVisible = visible
    }
}
