import Testing
@testable import VikunjaCore

struct QuickAddParserLabelTests {
    private let labels = [
        Label(id: 10, title: "hogar", hexColor: "ff0000"),
        Label(id: 11, title: "Trabajo Remoto", hexColor: "00ff00"),
        Label(id: 12, title: "dup", hexColor: "0000ff"),
        Label(id: 13, title: "Dup", hexColor: "00ffff"),
    ]

    @Test
    func `todoist at sign and vikunja asterisk find labels`() {
        #expect(QuickAddParser.tokenize("Leche @hogar", syntax: .todoist).map(\.kind) == [.label])
        #expect(QuickAddParser.tokenize("Leche *hogar", syntax: .vikunja).map(\.kind) == [.label])
    }

    @Test
    func `the other dialect's label symbol stays plain text`() {
        #expect(QuickAddParser.tokenize("Leche *hogar", syntax: .todoist).isEmpty)
        #expect(QuickAddParser.tokenize("Leche @hogar", syntax: .vikunja).isEmpty)
    }

    @Test
    func `an email address is not a label`() {
        #expect(QuickAddParser.tokenize("mandar a ana@x.com", syntax: .todoist).isEmpty)
    }

    @Test
    func `a matched label is applied and removed from the title`() {
        let result = QuickAddParser.parse("Leche @Hogar", projects: [], labels: labels, syntax: .todoist)

        #expect(result.labelIDs == [10])
        #expect(result.newLabelNames.isEmpty)
        #expect(result.title == "Leche")
    }

    @Test
    func `a quoted label name may contain spaces`() {
        let result = QuickAddParser.parse(
            "Revisar *\"Trabajo Remoto\"",
            projects: [],
            labels: labels,
            syntax: .vikunja,
        )

        #expect(result.labelIDs == [11])
        #expect(result.title == "Revisar")
    }

    @Test
    func `an unknown label is a new label to create and is removed from the title`() {
        let result = QuickAddParser.parse("Leche @compras", projects: [], labels: labels, syntax: .todoist)

        #expect(result.labelIDs.isEmpty)
        #expect(result.newLabelNames == ["compras"])
        #expect(result.title == "Leche")
        #expect(result.tokens.first?.resolution == .newLabel("compras"))
    }

    @Test
    func `an ambiguous label stays in the title and is not applied`() {
        let result = QuickAddParser.parse("Algo *dup", projects: [], labels: labels, syntax: .vikunja)

        #expect(result.labelIDs.isEmpty)
        #expect(result.newLabelNames.isEmpty)
        #expect(result.title == "Algo *dup")
        #expect(result.tokens.first?.resolution == .ambiguousLabel([labels[2], labels[3]]))
    }

    @Test
    func `several labels all apply and repeats count once`() {
        let result = QuickAddParser.parse(
            "Leche @hogar @Hogar @nuevo @NUEVO",
            projects: [],
            labels: labels,
            syntax: .todoist,
        )

        #expect(result.labelIDs == [10])
        #expect(result.newLabelNames == ["nuevo"])
        #expect(result.title == "Leche")
    }

    @Test
    func `labels combine with project and priority`() {
        let projects = [Project(id: 1, title: "Compras")]
        let result = QuickAddParser.parse(
            "Leche @hogar #Compras p1",
            projects: projects,
            labels: labels,
            syntax: .todoist,
        )

        #expect(result.title == "Leche")
        #expect(result.projectID == 1)
        #expect(result.priority == .urgent)
        #expect(result.labelIDs == [10])
    }

    @Test
    func `an escaped label sigil stays literal`() {
        let result = QuickAddParser.parse("Mencionar \\@ana", projects: [], labels: labels, syntax: .todoist)

        #expect(result.title == "Mencionar @ana")
        #expect(result.labelIDs.isEmpty)
        #expect(result.newLabelNames.isEmpty)
    }
}
