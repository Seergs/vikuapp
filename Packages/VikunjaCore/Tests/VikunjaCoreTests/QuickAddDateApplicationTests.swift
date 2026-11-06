import Foundation
import Testing
@testable import VikunjaCore

struct QuickAddDateApplicationTests {
    private func context() throws -> NaturalLanguageDateParser.Context {
        let zone = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 12,
        )))
        return .init(referenceDate: reference, timeZone: zone, languages: [.spanish, .english])
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `date and symbol ranges are removed together from original input`(_ syntax: QuickAddSyntax) throws {
        let input = syntax == .todoist ?
            "🥛 Café #\"mañana\" @tomorrow mañana a las 6pm p1" :
            "🥛 Café +\"mañana\" *tomorrow mañana a las 6pm !4"
        let result = try QuickAddParser.parse(
            input, projects: [Project(id: 1, title: "mañana")],
            labels: [Label(id: 2, title: "tomorrow", hexColor: "6449A2")],
            syntax: syntax, dateContext: context(),
        )
        #expect(result.title == "🥛 Café")
        #expect(result.projectID == 1)
        #expect(result.labelIDs == [2])
        #expect(result.priority == .urgent)
        #expect(result.dueDate == result.dateInterpretation.resolvedDate?.date)
        #expect(result.dateInterpretation.expressions.map(\.text) == ["mañana a las 6pm"])
        #expect(result.dateInterpretation.resolvedDate?.components.hour == 18)
    }

    @Test(arguments: ["\\#literal mañana", "mañana \\#literal"])
    func `date removal keeps symbol escapes correct`(_ input: String) throws {
        let result = try QuickAddParser.parse(input, projects: [], syntax: .todoist, dateContext: context())
        #expect(result.title == "#literal")
        #expect(result.dueDate != nil)
    }

    @Test func `unconfigured date recognition and disabled magic keep dates literal`() throws {
        let withoutContext = QuickAddParser.parse("Leche mañana", projects: [], syntax: .todoist)
        #expect(withoutContext.title == "Leche mañana")
        #expect(withoutContext.dueDate == nil)
        let disabled = try QuickAddParser.parse(
            "  Leche mañana #Compras  ",
            projects: [],
            syntax: nil,
            dateContext: context(),
        )
        #expect(disabled.title == "Leche mañana #Compras")
        #expect(disabled.dueDate == nil)
        #expect(disabled.dateInterpretation.status == .noMatch)
    }

    @Test(arguments: ["hoy o mañana", "31 de febrero", "en tres", "cada lunes", "no mañana", "03/04"])
    func `non applicable expressions remain literal`(_ expression: String) throws {
        let result = try QuickAddParser.parse(
            "Leche \(expression)",
            projects: [],
            syntax: .todoist,
            dateContext: context(),
        )
        #expect(result.title == "Leche \(expression)")
        #expect(result.dueDate == nil)
    }

    @Test func `unresolved shortcut names are protected from date removal`() throws {
        let result = try QuickAddParser.parse(
            "Leche #mañana",
            projects: [],
            syntax: .todoist,
            dateContext: context(),
        )
        #expect(result.title == "Leche #mañana")
        #expect(result.dueDate == nil)
    }

    @Test func `title can be empty after applying date and shortcuts`() throws {
        let result = try QuickAddParser.parse(
            "mañana #Compras p1", projects: [Project(id: 1, title: "Compras")],
            syntax: .todoist, dateContext: context(),
        )
        #expect(result.title.isEmpty)
        #expect(result.dueDate != nil)
    }

    @Test func `removal does not replace matching substrings in ordinary words`() throws {
        let result = try QuickAddParser.parse(
            "Comprar mañanita mañana",
            projects: [],
            syntax: .todoist,
            dateContext: context(),
        )
        #expect(result.title == "Comprar mañanita")
        #expect(result.dueDate != nil)
    }
}
