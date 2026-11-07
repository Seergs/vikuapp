import Testing
@testable import VikunjaCore

struct FilterQueryFormatterTests {
    @Test func `marks only resolved names even when the same text appears elsewhere`() {
        let segments = FilterQueryFormatter.displaySegments(
            "title = Work && project in 3, 999 && labels = 7 && priority = 3",
            labelTitle: { _ in "Work" }, projectTitle: { $0 == 3 ? "Work" : nil },
        )

        #expect(segments.map(\.text).joined()
            == "title = Work && project in Work, 999 && labels = Work && priority = 3")
        #expect(segments.filter(\.isResolvedName).map(\.text) == ["Work", "Work"])
        #expect(segments.filter { !$0.isResolvedName }.map(\.text)
            == ["title = Work && project in ", ", 999 && labels = ", " && priority = 3"])
    }

    @Test func `resolved names retain literal quotes Unicode and query syntax in a single segment`() {
        let segments = FilterQueryFormatter.displaySegments(
            "project = 3", labelTitle: { _ in nil }, projectTitle: { _ in #"🏠 "Home" && labels = 7"# },
        )

        #expect(segments.filter(\.isResolvedName).map(\.text) == [#""🏠 \"Home\" && labels = 7""#])
        #expect(segments.first?.text == "project = ")
        #expect(segments.first?.isResolvedName == false)
    }

    @Test(arguments: ["", "project in 3, 999 && labels = 7", "title = 'project = 3'"])
    func `queries without resolved names have no highlighted segments`(query: String) {
        let segments = FilterQueryFormatter.displaySegments(
            query, labelTitle: { _ in nil }, projectTitle: { _ in nil },
        )
        #expect(segments.map(\.text).joined() == query)
        #expect(!segments.contains { $0.isResolvedName })
    }

    private func format(_ query: String) -> String {
        FilterQueryFormatter.displayQuery(
            query,
            labelTitle: { [7: "Urgent", 9: "Home"][$0] },
            projectTitle: { [3: "Work", 4: "Personal"][$0] },
        )
    }

    @Test(arguments: ["=", "!=", "in", "not in", "?=", "?!="])
    func `resolves project and label equality and set operators`(operation: String) {
        #expect(format("project \(operation) 3 && labels \(operation) 7")
            == "project \(operation) Work && labels \(operation) Urgent")
    }

    @Test func `preserves whitespace grouping and unrelated values`() {
        let query = "(project in 3,4 || labels not in 7, 9)\n && priority >= 3 && project=3"
        #expect(format(query)
            == "(project in Work,Personal || labels not in Urgent, Home)\n && priority >= 3 && project=Work")
    }

    @Test func `unknown IDs survive alongside resolved IDs`() {
        #expect(format("project in 3, 999 && labels in 42, 7")
            == "project in Work, 999 && labels in 42, Urgent")
    }

    @Test(arguments: [
        "", " \n ", "priority = 3 && due_date < now/d",
        "title = 'project = 3 && labels = 7'",
        #"description like "escaped \" labels = 7 || project = 3""#,
        "project > 3", "labels like 7", "project = 3oops",
        "project = 9999999999999999999999999999999",
        "project = 3, 4", "project in 3,", "labels in 7,,9",
        "project in 3, unknown", "project = '3", "project = 3 extra",
        "unknown_project = 3", "project_id = 3", "assignees = 3",
    ])
    func `preserves unsupported fields malformed values and quoted text`(query: String) {
        #expect(format(query) == query)
    }

    @Test func `supports case insensitive fields and quoted IDs`() {
        #expect(format("PROJECT IN '3', \"4\" && LaBeLs=7")
            == "PROJECT IN Work, Personal && LaBeLs=Urgent")
    }

    @Test func `missing or empty titles preserve the raw query`() {
        let query = "project = 3 && labels = 7"
        let result = FilterQueryFormatter.displayQuery(query, labelTitle: { _ in nil }, projectTitle: { _ in "" })
        #expect(result == query)
    }

    @Test func `quotes and escapes names without interpreting them as query syntax`() {
        let query = "project = 3 && labels = 7 && priority = 3"
        let result = FilterQueryFormatter.displayQuery(
            query,
            labelTitle: { _ in #"A "quote", a \ path && labels = 7"# },
            projectTitle: { _ in "Work (team)" },
        )
        let expected = #"project = "Work (team)" && labels = "A \"quote\", a \\ path && labels = 7""#
            + " && priority = 3"
        #expect(result == expected)
        #expect(query == "project = 3 && labels = 7 && priority = 3")
    }

    @Test func `handles Unicode names and duplicate titles`() {
        #expect(FilterQueryFormatter.displayQuery(
            "project in 3, 4 && labels = 7",
            labelTitle: { _ in "日本語" }, projectTitle: { _ in "Trabajo personal 🏠" },
        ) == "project in \"Trabajo personal 🏠\", \"Trabajo personal 🏠\" && labels = 日本語")
    }
}
