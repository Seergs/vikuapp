import Foundation
import Testing
@testable import VikunjaCore

struct NaturalLanguageDateParserTests {
    private typealias Parser = NaturalLanguageDateParser

    private func context(
        year: Int = 2026, month: Int = 11, day: Int = 5,
        hour: Int = 12, minute: Int = 0, zone: String = "America/Mexico_City",
        languages: Set<Parser.Language> = [.spanish, .english],
    ) throws -> Parser.Context {
        let timeZone = try #require(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: 0,
        )))
        return Parser.Context(referenceDate: date, timeZone: timeZone, languages: languages)
    }

    private func expectDate(
        _ text: String, year: Int = 2026, month: Int = 11, day: Int,
        hour: Int = 23, minute: Int = 59, second: Int = 59,
        explicit: Bool = false, context supplied: Parser.Context? = nil,
    ) throws {
        let context = try supplied ?? context()
        let result = Parser.parse(text, context: context)
        #expect(result.status == .resolved, "\(text): \(result)")
        let resolved = try #require(result.resolvedDate)
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        #expect(resolved.components == components, "\(text)")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        #expect(resolved.date == calendar.date(from: components))
        #expect(resolved.hasExplicitTime == explicit)
        #expect(resolved.precision == (explicit ? .minute : .day))
        #expect(resolved.timeZoneIdentifier == context.timeZone.identifier)
    }

    @Test(arguments: ["hoy", "today", "HOY", "Comprar leche hoy"])
    func today(_ text: String) throws {
        try expectDate(text, day: 5)
    }

    @Test(arguments: ["mañana", "manana", "tomorrow", "Comprar leche tomorrow", "MAÑANA"])
    func tomorrow(_ text: String) throws {
        try expectDate(text, day: 6)
    }

    @Test(arguments: ["pasado mañana", "pasado manana", "day after tomorrow"])
    func `day after tomorrow`(_ text: String) throws {
        try expectDate(text, day: 7)
        #expect(try Parser.parse(text, context: context()).expressions.count == 1)
    }

    @Test(arguments: [
        "sábado",
        "sabado",
        "el sábado",
        "Saturday",
        "on Saturday",
        "próximo sábado",
        "next Saturday",
        "sábado que viene",
        "este sábado",
        "this Saturday",
    ])
    func weekdays(_ text: String) throws {
        try expectDate(text, day: 7)
    }

    @Test func `weekday boundaries`() throws {
        let saturday = try context(day: 7)
        try expectDate("sábado", day: 7, context: saturday)
        try expectDate("próximo sábado", day: 14, context: saturday)
        try expectDate("next Saturday", day: 14, context: saturday)
        let result = try Parser.parse("este sábado", context: context(day: 8))
        #expect(result.status == .ambiguous)
        guard case let .ambiguous(issue, alternatives) = result.expressions.first?.outcome else {
            Issue.record("Expected a past-day ambiguity")
            return
        }
        #expect(issue == .pastDayInCurrentWeek)
        #expect(alternatives.map(\.components.day) == [7, 14])
    }

    @Test func `relative quantities`() throws {
        try expectDate("en 3 días", day: 8)
        try expectDate("en tres dias", day: 8)
        try expectDate("en 0 días", day: 5)
        try expectDate("in a week", day: 12)
        try expectDate("en una semana", day: 12)
        try expectDate("in two weeks", day: 19)
        try expectDate("en dos meses", year: 2027, month: 1, day: 5)
        try expectDate("in an year", year: 2027, day: 5)
        try expectDate("in twenty-one days", day: 26)
        try expectDate("in twenty nine days", month: 12, day: 4)
        try expectDate("in thirty days", month: 12, day: 5)
        try expectDate("en treinta días", month: 12, day: 5)
        try expectDate("en 45 días", month: 12, day: 20)
    }

    @Test func `month and year clamping`() throws {
        let january = try context(year: 2027, month: 1, day: 31)
        try expectDate("en un mes", year: 2027, month: 2, day: 28, context: january)
        try expectDate("en dos meses", year: 2027, month: 3, day: 31, context: january)
        let leap = try context(year: 2028, month: 2, day: 29)
        try expectDate("en un año", year: 2029, month: 2, day: 28, context: leap)
    }

    @Test func `calendar dates`() throws {
        try expectDate("15 de noviembre", day: 15)
        try expectDate("November 15", day: 15)
        try expectDate("November 4", year: 2027, day: 4)
        try expectDate("15 de noviembre de 2027", year: 2027, day: 15)
        try expectDate("November 15, 2027", year: 2027, day: 15)
        try expectDate("2020-11-15", year: 2020, day: 15)
        try expectDate("29 de febrero", year: 2028, month: 2, day: 29)
        try expectDate(
            "February 29",
            year: 2104,
            month: 2,
            day: 29,
            context: context(year: 2097, month: 3, day: 1),
        )
    }

    @Test func `explicit times`() throws {
        try expectDate("mañana a las 18:30", day: 6, hour: 18, minute: 30, second: 0, explicit: true)
        try expectDate("tomorrow at 6 pm", day: 6, hour: 18, minute: 0, second: 0, explicit: true)
        try expectDate("mañana 18:30", day: 6, hour: 18, minute: 30, second: 0, explicit: true)
        try expectDate("a las 18:00", day: 5, hour: 18, minute: 0, second: 0, explicit: true)
        try expectDate("a las 9", day: 6, hour: 9, minute: 0, second: 0, explicit: true)
        try expectDate("hoy a las 9", day: 5, hour: 9, minute: 0, second: 0, explicit: true)
        try expectDate("noon", day: 5, hour: 12, minute: 0, second: 0, explicit: true)
        try expectDate("midnight", day: 6, hour: 0, minute: 0, second: 0, explicit: true)
        try expectDate("mañana medianoche", day: 6, hour: 0, minute: 0, second: 0, explicit: true)
        try expectDate("2027-11-15 at 6 pm", year: 2027, day: 15, hour: 18, minute: 0, second: 0, explicit: true)
    }

    @Test(arguments: [
        ("6pm", "6 pm"), ("6PM", "6 PM"), ("6am", "6 am"), ("6:30pm", "6:30 pm"),
        ("12am", "12 am"), ("12pm", "12 pm"), ("13pm", "13 pm"), ("0am", "0 am"),
        ("tomorrow at 6pm", "tomorrow at 6 pm"), ("mañana a las 6:30pm", "mañana a las 6:30 pm"),
    ])
    func `attached meridiem matches spaced form`(_ compact: String, _ spaced: String) throws {
        let context = try context()
        let result = Parser.parse(compact, context: context)
        let baseline = Parser.parse(spaced, context: context)
        #expect(result.status == baseline.status)
        #expect(result.expressions.map(\.outcome) == baseline.expressions.map(\.outcome))
        #expect(result.expressions.count == 1)
        let expression = try #require(result.expressions.first)
        #expect(expression.text == compact)
        #expect(String(compact[expression.range]) == compact)
    }

    @Test(arguments: ["task6pm", "6pmish", "6pm_extra", "https://example.com/6pm", "6pm@example.com"])
    func `attached meridiem respects word and address boundaries`(_ text: String) throws {
        #expect(try Parser.parse(text, context: context()).status == .noMatch)
    }

    @Test(arguments: [
        "31 de febrero",
        "February 30",
        "2026-02-29",
        "2026-13-01",
        "2026-00-01",
        "mañana a las 25:00",
        "tomorrow at 12:99",
        "13 pm",
        "18:30:15",
    ])
    func `invalid expressions`(_ text: String) throws {
        let result = try Parser.parse(text, context: context())
        #expect(result.status == .invalid, "\(text): \(result)")
        #expect(result.resolvedDate == nil)
    }

    @Test(arguments: [
        "cada lunes",
        "every Monday",
        "más tarde",
        "soon",
        "este fin de semana",
        "early next month",
        "en un mes y dos días",
        "in one month and two days",
        "en 1.5 meses",
        "en -3 días",
        "en cuarenta y cinco días",
        "en two días",
        "mañana at 6 pm",
        "03/04",
        "03/04/2027",
        "mañana a las 18:00 CET",
        "tomorrow at 6 pm America/New_York",
        "no mañana",
        "quizá el lunes",
        "si puedo el viernes",
        "if I can on Friday",
    ])
    func `unsupported expressions`(_ text: String) throws {
        let result = try Parser.parse(text, context: context())
        #expect(result.status == .unsupported, "\(text): \(result)")
        #expect(result.resolvedDate == nil)
    }

    @Test(arguments: ["en tres", "in three", "mañana a las", "tomorrow at", "mañana a las 18:"])
    func `incomplete expressions`(_ text: String) throws {
        #expect(try Parser.parse(text, context: context()).status == .incomplete)
    }

    @Test(arguments: ["en 999999999999999999999999 días", "en 999999999 años", "0001-01-01"])
    func `out of range`(_ text: String) throws {
        let result = try Parser.parse(text, context: context())
        #expect(result.expressions.first?.outcome == .invalid(.outOfRange))
    }

    @Test(arguments: ["hoy o mañana", "del lunes al viernes", "from Monday to Friday", "hoy 2027-11-15"])
    func `multiple dates have no winner`(_ text: String) throws {
        let result = try Parser.parse(text, context: context())
        #expect(result.status == .ambiguous)
        #expect(result.resolvedDate == nil)
    }

    @Test(arguments: [
        "Preparar informe",
        "tomorrowish",
        "mañanita",
        "mar",
        "https://example.org/mañana",
        "tomorrow@example.com",
        "www.example.com/tomorrow",
    ])
    func `ordinary text and addresses`(_ text: String) throws {
        #expect(try Parser.parse(text, context: context()).status == .noMatch)
    }

    @Test func `language configuration and unicode ranges`() throws {
        #expect(try Parser.parse("tomorrow", context: context(languages: [.spanish])).status == .noMatch)
        #expect(try Parser.parse("mañana", context: context(languages: [.english])).status == .noMatch)
        #expect(try Parser.parse("2027-11-15", context: context(languages: [])).status == .noMatch)
        let input = "🥛 Café, MAÑANA!"
        let result = try Parser.parse(input, context: context())
        let expression = try #require(result.expressions.first)
        #expect(String(input[expression.range]) == "MAÑANA")
        #expect(expression.text == "MAÑANA")
        #expect(expression.ruleIDs.contains("R09"))
        #expect(expression.language == .spanish)
        #expect(input == "🥛 Café, MAÑANA!")
    }

    @Test func `protected tokens`() throws {
        let input = "Comprar #\"mañana\" tomorrow"
        let protected = try #require(input.range(of: "#\"mañana\""))
        let result = try Parser.parse(input, context: context(), protecting: [protected])
        #expect(result.expressions.map(\.text) == ["tomorrow"])
        #expect(result.status == .resolved)
    }

    @Test func `daylight saving transitions`() throws {
        let spring = try context(year: 2027, month: 3, day: 13, zone: "America/New_York")
        let gap = Parser.parse("tomorrow at 02:30", context: spring)
        guard case let .invalid(.nonexistentLocalTime(suggestion)) = gap.expressions.first?.outcome else {
            Issue.record("Expected nonexistent local time, got \(gap)")
            return
        }
        #expect(suggestion != nil)
        let autumn = try context(year: 2026, month: 10, day: 31, zone: "America/New_York")
        let fold = Parser.parse("tomorrow at 01:30", context: autumn)
        guard case let .ambiguous(.repeatedLocalTime, alternatives) = fold.expressions.first?.outcome else {
            Issue.record("Expected repeated local time, got \(fold)")
            return
        }
        #expect(alternatives.count == 2)
        #expect(try alternatives.last?.date.timeIntervalSince(#require(alternatives.first?.date)) == 3600)
        try expectDate("tomorrow", year: 2027, month: 3, day: 14, context: spring)
    }

    @Test func `reference zone and midnight are explicit`() throws {
        let mexico = try context(hour: 23, minute: 59)
        try expectDate("mañana", day: 6, context: mexico)
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let sameInstant = Parser.Context(referenceDate: mexico.referenceDate, timeZone: tokyo, languages: [.spanish])
        try expectDate("mañana", day: 7, context: sameInstant)
        let first = Parser.parse("mañana", context: mexico)
        #expect(first == Parser.parse("mañana", context: mexico))
    }

    @Test func `composed written dates and minute validation`() throws {
        try expectDate("15 de noviembre 18:30", day: 15, hour: 18, minute: 30, second: 0, explicit: true)
        try expectDate("November 15 18:30", day: 15, hour: 18, minute: 30, second: 0, explicit: true)
        for text in ["a las 18:9", "tomorrow at 18:999", "at 999999999999999999999"] {
            #expect(try Parser.parse(text, context: context()).status == .invalid)
        }
        let context = try context()
        let exact = Parser.Context(
            referenceDate: context.referenceDate.addingTimeInterval(1),
            timeZone: context.timeZone, languages: [.english],
        )
        try expectDate("noon", day: 6, hour: 12, minute: 0, second: 0, explicit: true, context: exact)
    }

    @Test(arguments: [
        ("domingo", "Sunday", 8), ("lunes", "Monday", 9), ("martes", "Tuesday", 10),
        ("miércoles", "Wednesday", 11), ("jueves", "Thursday", 5), ("viernes", "Friday", 6),
        ("sábado", "Saturday", 7),
    ])
    func `weekday vocabulary`(_ spanish: String, _ english: String, _ day: Int) throws {
        try expectDate(spanish, day: day)
        try expectDate(english, day: day)
    }

    @Test(arguments: [
        ("enero", "January"), ("febrero", "February"), ("marzo", "March"), ("abril", "April"),
        ("mayo", "May"), ("junio", "June"), ("julio", "July"), ("agosto", "August"),
        ("septiembre", "September"), ("octubre", "October"), ("noviembre", "November"), ("diciembre", "December"),
    ].enumerated().map { ($0.offset + 1, $0.element.0, $0.element.1) })
    func `month vocabulary`(_ month: Int, _ spanish: String, _ english: String) throws {
        try expectDate("15 de \(spanish) de 2027", year: 2027, month: month, day: 15)
        try expectDate("\(english) 15, 2027", year: 2027, month: month, day: 15)
    }

    private static let spanishNumberWords = [
        "uno",
        "dos",
        "tres",
        "cuatro",
        "cinco",
        "seis",
        "siete",
        "ocho",
        "nueve",
        "diez",
        "once",
        "doce",
        "trece",
        "catorce",
        "quince",
        "dieciséis",
        "diecisiete",
        "dieciocho",
        "diecinueve",
        "veinte",
        "veintiuno",
        "veintidós",
        "veintitrés",
        "veinticuatro",
        "veinticinco",
        "veintiséis",
        "veintisiete",
        "veintiocho",
        "veintinueve",
        "treinta",
    ]
    private static let englishNumberWords = [
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "ten",
        "eleven",
        "twelve",
        "thirteen",
        "fourteen",
        "fifteen",
        "sixteen",
        "seventeen",
        "eighteen",
        "nineteen",
        "twenty",
        "twenty-one",
        "twenty-two",
        "twenty-three",
        "twenty-four",
        "twenty-five",
        "twenty-six",
        "twenty-seven",
        "twenty-eight",
        "twenty-nine",
        "thirty",
    ]
    @Test func `number word vocabulary`() throws {
        let january = try context(year: 2027, month: 1, day: 1)
        for (index, pair) in zip(Self.spanishNumberWords, Self.englishNumberWords).enumerated() {
            try expectDate("en \(pair.0) días", year: 2027, month: 1, day: index + 2, context: january)
            try expectDate("in \(pair.1) days", year: 2027, month: 1, day: index + 2, context: january)
        }
        try expectDate("en veintiún días", day: 26)
        try expectDate("en veintiuna semanas", year: 2027, month: 4, day: 1)
    }

    @Test func `unsupported constructions do not leak partial dates`() throws {
        for text in [
            "cada dos lunes",
            "every other Monday",
            "todos los lunes",
            "si el viernes",
            "en two days",
            "in dos días",
        ] {
            let result = try Parser.parse(text, context: context())
            #expect(result.status == .unsupported, "\(text): \(result)")
            #expect(result.resolvedDate == nil)
        }
        let ordinary = "Trabajar en casa mañana y organizar días libres"
        #expect(try Parser.parse(ordinary, context: context()).expressions.map(\.text) == ["mañana"])
        try expectDate("November 15, buy groceries", day: 15)
    }

    @Test func `range limits and serialization`() throws {
        for text in [
            "10000-01-01",
            "999999999999999999999999-01-01",
            "15 de noviembre de 999999999999999999999999",
        ] {
            #expect(try Parser.parse(text, context: context()).expressions.first?.outcome == .invalid(.outOfRange))
        }
        let utc = try context(zone: "UTC")
        for text in ["0002-01-01", "9999-12-31", "2028-02-29"] {
            let resolved = try #require(Parser.parse(text, context: utc).resolvedDate)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(Date.self, from: encoder.encode(resolved.date)) == resolved.date)
            #expect(try String(bytes: encoder.encode(resolved.date), encoding: .utf8)?.contains(text) == true)
        }
        let invalidContext = Parser.Context(
            referenceDate: Date(timeIntervalSinceReferenceDate: .infinity),
            timeZone: utc.timeZone,
            languages: [.english],
        )
        #expect(Parser.parse("tomorrow", context: invalidContext).expressions.first?.outcome == .invalid(.outOfRange))
    }
}
