import Foundation
@testable import Tasks
import Testing
import VikuDesignSystem
import VikunjaCore

@MainActor
struct QuickAddDateHighlightTests {
    private func model(syntax: QuickAddSyntax? = .todoist) throws -> QuickAddTaskViewModel {
        let zone = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 12,
        )))
        return QuickAddTaskViewModel(
            preselectedProjectID: 1,
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            dateParsingContext: .init(referenceDate: reference, timeZone: zone, languages: [.spanish, .english]),
        )
    }

    private func dates(in highlights: QuickAddTitleHighlights) -> [String] {
        highlights.spans.filter { $0.style == .date }.map { String(highlights.input[$0.range]) }
    }

    @Test(arguments: ["mañana", "pasado mañana", "mañana a las 6pm", "tomorrow at 6:30pm", "en dos meses"])
    func `highlights the complete resolved expression`(_ phrase: String) throws {
        let model = try model()
        model.input = "🥛 Comprar café \(phrase)!"
        let highlights = model.titleHighlights
        #expect(highlights.input == model.input)
        #expect(dates(in: highlights) == [phrase])
        for span in highlights.spans {
            let utf16Range = NSRange(span.range, in: highlights.input)
            #expect((highlights.input as NSString).substring(with: utf16Range) == phrase)
        }
    }

    @Test func `developer panel can stay hidden while date is highlighted`() async throws {
        let model = try model()
        model.input = "Comprar leche mañana"
        #expect(!model.isDatePreviewEnabled)
        #expect(dates(in: model.titleHighlights) == ["mañana"])
        let saved = try #require(await model.save())
        #expect(saved.title == "Comprar leche mañana")
        #expect(saved.dueDate == nil)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `date does not consume project or label names`(_ syntax: QuickAddSyntax) throws {
        let model = try model(syntax: syntax)
        model.input = syntax == .todoist ?
            "🥛 #\"mañana\" @tomorrow pasado mañana p1" : "🥛 +\"mañana\" *tomorrow pasado mañana !4"
        let highlights = model.titleHighlights
        #expect(dates(in: highlights) == ["pasado mañana"])
        #expect(highlights.spans.count == 4)
        let date = try #require(highlights.spans.first { $0.style == .date })
        for shortcut in highlights.spans where shortcut.style != .date {
            #expect(!shortcut.range.overlaps(date.range))
        }
    }

    @Test(arguments: [
        "hoy o mañana", "31 de febrero", "mañana a las 25:00", "en tres", "cada lunes",
        "no mañana", "tomorrow 2027-11-15", "Preparar informe",
    ])
    func `ambiguous invalid or incomplete dates stay plain`(_ text: String) throws {
        let model = try model()
        model.input = text
        #expect(dates(in: model.titleHighlights).isEmpty)
        #expect(model.titleHighlights.input == text)
    }

    @Test func `disabling magic leaves all text plain`() async throws {
        let model = try model(syntax: nil)
        model.input = "Comprar leche mañana #Compras p1"
        #expect(model.titleHighlights.spans.isEmpty)
        let saved = try #require(await model.save())
        #expect(saved.title == model.input)
        #expect(saved.dueDate == nil)
    }

    @Test func `edits replace ranges and remove obsolete date highlights`() throws {
        let model = try model()
        model.input = "Leche mañana"
        let original = model.titleHighlights
        model.input = "🥛 Café y leche mañana"
        #expect(model.titleHighlights.input != original.input)
        #expect(dates(in: model.titleHighlights) == ["mañana"])
        #expect(model.titleHighlights.spans.first?.range != original.spans.first?.range)
        model.input = "🥛 Café y leche mañana a las 25:00"
        #expect(dates(in: model.titleHighlights).isEmpty)
        model.input = "🥛 Café y leche"
        #expect(model.titleHighlights.spans.isEmpty)
    }

    @Test func `date and shortcut styles use their design system tokens`() {
        #expect(QuickAddTitleHighlights.Style.date.tint(in: .standard) == VikuPalette.standard.dateHighlightText)
        #expect(QuickAddTitleHighlights.Style.date.tint(in: .warm) == VikuPalette.warm.dateHighlightText)
        let project = QuickAddTitleHighlights.Style.shortcut(.project(Project(id: 1, title: "Compras")))
        #expect(project.tint(in: .standard) == VikuPalette.standard.brand)
        #expect(QuickAddTitleHighlights.Style.shortcut(.superseded).tint(in: .warm) == nil)
    }
}
