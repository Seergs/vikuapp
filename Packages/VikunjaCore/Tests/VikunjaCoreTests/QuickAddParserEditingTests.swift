import Testing
@testable import VikunjaCore

struct QuickAddParserEditingTests {
    @Test
    func `replaces the project shortcut in place`() {
        let result = QuickAddParser.settingProject("Trabajo", in: "Leche +Compras !2", syntax: .vikunja)
        #expect(result == "Leche +Trabajo !2")
    }

    @Test
    func `quotes a project name that has spaces`() {
        let result = QuickAddParser.settingProject("Lista del super", in: "Pan", syntax: .todoist)
        #expect(result == "Pan #\"Lista del super\"")
        #expect(QuickAddParser.tokenize(result, syntax: .todoist).first?.value == "Lista del super")
    }

    @Test
    func `appends a project shortcut when the input has none`() {
        #expect(QuickAddParser.settingProject("Compras", in: "Leche  ", syntax: .vikunja) == "Leche +Compras")
        #expect(QuickAddParser.settingProject("Compras", in: "", syntax: .vikunja) == "+Compras")
    }

    @Test
    func `removes the project shortcut and the space before it`() {
        #expect(QuickAddParser.settingProject(nil, in: "Leche +Compras", syntax: .vikunja) == "Leche")
        #expect(QuickAddParser.settingProject(nil, in: "+Compras Leche", syntax: .vikunja) == " Leche")
    }

    @Test
    func `leaves the input alone when there is nothing to remove`() {
        #expect(QuickAddParser.settingProject(nil, in: "Leche", syntax: .vikunja) == "Leche")
    }

    @Test
    func `only the first project shortcut is rewritten`() {
        let result = QuickAddParser.settingProject("Trabajo", in: "A +Compras +Otro", syntax: .vikunja)
        #expect(result == "A +Trabajo +Otro")
    }

    @Test
    func `writes the todoist priority digit`() {
        #expect(QuickAddParser.settingPriority(.high, in: "Leche p1", syntax: .todoist) == "Leche p2")
        #expect(QuickAddParser.settingPriority(.urgent, in: "Leche", syntax: .todoist) == "Leche p1")
    }

    @Test
    func `writes the vikunja priority digit`() {
        #expect(QuickAddParser.settingPriority(.doNow, in: "Leche", syntax: .vikunja) == "Leche !5")
        #expect(QuickAddParser.settingPriority(.medium, in: "Leche !4", syntax: .vikunja) == "Leche !2")
    }

    @Test
    func `unset priority removes the shortcut`() {
        #expect(QuickAddParser.settingPriority(.unset, in: "Leche !3 hoy", syntax: .vikunja) == "Leche hoy")
    }

    @Test
    func `a written priority reads back as the same priority`() {
        for syntax in QuickAddSyntax.allCases {
            for priority in VikunjaTask.Priority.allCases where priority != .unset {
                let text = QuickAddParser.settingPriority(priority, in: "Leche", syntax: syntax)
                let read = QuickAddParser.parse(text, projects: [], syntax: syntax).priority
                let expected = syntax.priority(forLevel: syntax.level(for: priority) ?? 0)
                #expect(read == expected)
            }
        }
    }
}
