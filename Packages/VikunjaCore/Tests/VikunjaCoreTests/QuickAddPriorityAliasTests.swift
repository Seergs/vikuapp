import Testing
@testable import VikunjaCore

struct QuickAddPriorityAliasTests {
    @Test(arguments: 1 ... 4)
    func `todoist aliases resolve like canonical priorities`(level: Int) throws {
        let input = "Buy milk !!\(level)"
        let result = QuickAddParser.parse(input, projects: [], syntax: .todoist)
        let canonical = QuickAddParser.parse("Buy milk p\(level)", projects: [], syntax: .todoist)
        #expect(result.title == "Buy milk")
        #expect(result.priority == canonical.priority)
        let token = try #require(result.tokens.first?.token)
        #expect(token.kind == .priority)
        #expect(token.value == String(level))
        #expect(String(input[token.range]) == "!!\(level)")
    }

    @Test(arguments: ["!", "!2", "!!", "!!0", "!!5", "!!22", "!!2foo", "!!2!", "milk!!2", "!!!2"])
    func `invalid aliases and punctuation remain literal`(input: String) {
        let result = QuickAddParser.parse(input, projects: [], syntax: .todoist)
        #expect(result.tokens.isEmpty)
        #expect(result.priority == nil)
        #expect(result.title == input)
    }

    @Test
    func `aliases work at the start and across whitespace`() {
        let result = QuickAddParser.parse("!!2\nBuy milk", projects: [], syntax: .todoist)
        #expect(result.priority == .high)
        #expect(result.title == "Buy milk")
    }

    @Test
    func `escaped aliases remain literal`() {
        let input = #"Buy milk \!!2"#
        let result = QuickAddParser.parse(input, projects: [], syntax: .todoist)
        #expect(result.priority == nil)
        #expect(result.title == "Buy milk !!2")
        #expect(QuickAddParser.searchQuery(input, syntax: .todoist).text == "Buy milk !!2")
        #expect(QuickAddParser.searchQuery(input, syntax: .todoist).priority == nil)
        #expect(QuickAddParser.parse(#"Buy milk \!2"#, projects: [], syntax: .todoist).title == #"Buy milk \!2"#)
    }

    @Test
    func `aliases remain literal in vikunja and disabled modes`() {
        for syntax: QuickAddSyntax? in [.vikunja, nil] {
            let result = QuickAddParser.parse("Buy milk !!2", projects: [], syntax: syntax)
            #expect(result.priority == nil)
            #expect(result.title == "Buy milk !!2")
        }
        #expect(QuickAddParser.parse("Buy milk !2", projects: [], syntax: .vikunja).priority == .medium)
    }

    @Test(arguments: ["p3 !!1", "!!3 p1"])
    func `first priority wins across aliases`(shortcuts: String) {
        let result = QuickAddParser.parse("Buy milk \(shortcuts)", projects: [], syntax: .todoist)
        #expect(result.priority == .medium)
        #expect(result.tokens.map(\.resolution) == [.priority(.medium), .superseded])
        #expect(result.title == "Buy milk \(shortcuts.split(separator: " ")[1])")
    }

    @Test
    func `picker replaces and removes complete aliases`() {
        #expect(QuickAddParser.settingPriority(.urgent, in: "Buy milk !!2", syntax: .todoist) == "Buy milk p1")
        #expect(QuickAddParser.settingPriority(.unset, in: "Buy milk !!2", syntax: .todoist) == "Buy milk")
    }

    @Test
    func `search applies aliases and removes their entire ranges`() {
        let query = QuickAddParser.searchQuery("Buy milk !!2 p1", syntax: .todoist)
        #expect(query.text == "Buy milk")
        #expect(query.priority == .high)
        let disabled = QuickAddParser.searchQuery("Buy milk !!2", syntax: nil)
        #expect(disabled.text == "Buy milk !!2")
        #expect(disabled.priority == nil)
    }
}
