import Testing
@testable import VikunjaCore

struct QuickAddParserTests {
    private let projects = [
        Project(id: 1, title: "Compras"),
        Project(id: 2, title: "Lista del super"),
        Project(id: 3, title: "Trabajo"),
        Project(id: 4, title: "Dup"),
        Project(id: 5, title: "dup"),
    ]

    // MARK: - Tokenizing

    @Test
    func `todoist dialect finds hash projects and p priorities`() {
        let input = "Comprar leche #Compras p1"
        let tokens = QuickAddParser.tokenize(input, syntax: .todoist)

        #expect(tokens.map(\.kind) == [.project, .priority])
        #expect(tokens.map(\.value) == ["Compras", "1"])
        #expect(String(input[tokens[0].range]) == "#Compras")
        #expect(String(input[tokens[1].range]) == "p1")
    }

    @Test
    func `vikunja dialect finds plus projects and bang priorities`() {
        let input = "Comprar leche +Compras !5"
        let tokens = QuickAddParser.tokenize(input, syntax: .vikunja)

        #expect(tokens.map(\.kind) == [.project, .priority])
        #expect(tokens.map(\.value) == ["Compras", "5"])
    }

    @Test
    func `the other dialect's symbols stay plain text`() {
        #expect(QuickAddParser.tokenize("Comprar #Compras", syntax: .vikunja).isEmpty)
        #expect(QuickAddParser.tokenize("Comprar +Compras", syntax: .todoist).isEmpty)
        #expect(QuickAddParser.tokenize("Comprar p2", syntax: .vikunja).isEmpty)
    }

    @Test
    func `quoted project names may contain spaces`() {
        let input = "Comprar #\"Lista del super\""
        let tokens = QuickAddParser.tokenize(input, syntax: .todoist)

        #expect(tokens.count == 1)
        #expect(tokens[0].value == "Lista del super")
        #expect(String(input[tokens[0].range]) == "#\"Lista del super\"")
    }

    @Test
    func `shortcuts inside words are not tokens`() {
        #expect(QuickAddParser.tokenize("mail a foo#bar", syntax: .todoist).isEmpty)
        #expect(QuickAddParser.tokenize("mail a foo+bar", syntax: .vikunja).isEmpty)
    }

    @Test
    func `out of range levels and words starting with p are not priorities`() {
        #expect(QuickAddParser.tokenize("p5 pay p", syntax: .todoist).isEmpty)
        #expect(QuickAddParser.tokenize("!6 ! !!", syntax: .vikunja).isEmpty)
    }

    @Test
    func `a lone sigil is not a token`() {
        #expect(QuickAddParser.tokenize("# ! + alone", syntax: .todoist).isEmpty)
    }

    // MARK: - Resolution

    @Test
    func `matches a project ignoring case and accents`() {
        let result = QuickAddParser.parse("Leche #COMPRAS", projects: projects, syntax: .todoist)

        #expect(result.projectID == 1)
        #expect(result.title == "Leche")
    }

    @Test
    func `matches quoted multi word projects`() {
        let result = QuickAddParser.parse(
            "Pan #\"Lista del super\"",
            projects: projects,
            syntax: .todoist,
        )

        #expect(result.projectID == 2)
        #expect(result.title == "Pan")
    }

    @Test
    func `an ambiguous project stays in the title and is not applied`() {
        let result = QuickAddParser.parse("Algo #dup", projects: projects, syntax: .todoist)

        #expect(result.projectID == nil)
        #expect(result.title == "Algo #dup")
        #expect(result.tokens.first?.resolution == .ambiguousProject([projects[3], projects[4]]))
    }

    @Test
    func `an unknown project stays in the title`() {
        let result = QuickAddParser.parse("Algo +Nope", projects: projects, syntax: .vikunja)

        #expect(result.projectID == nil)
        #expect(result.title == "Algo +Nope")
        #expect(result.tokens.first?.resolution == .unmatchedProject)
    }

    @Test
    func `todoist p1 is urgent and p4 is low`() {
        let urgent = QuickAddParser.parse("Algo p1", projects: projects, syntax: .todoist)
        let low = QuickAddParser.parse("Algo p4", projects: projects, syntax: .todoist)

        #expect(urgent.priority == .urgent)
        #expect(low.priority == .low)
        #expect(urgent.title == "Algo")
    }

    @Test
    func `vikunja bang 5 is the server's do now level`() {
        let result = QuickAddParser.parse("Algo !5", projects: projects, syntax: .vikunja)

        #expect(result.priority == .doNow)
        #expect(result.title == "Algo")
    }

    @Test
    func `only the first token of a kind applies and later ones stay in the title`() {
        let result = QuickAddParser.parse(
            "Algo #Compras #Trabajo",
            projects: projects,
            syntax: .todoist,
        )

        #expect(result.projectID == 1)
        #expect(result.title == "Algo #Trabajo")
        #expect(result.tokens.last?.resolution == .superseded)
    }

    // MARK: - Title

    @Test
    func `escaped sigils are kept as literal text without the backslash`() {
        let result = QuickAddParser.parse(
            "Pedir \\#1 en la tienda",
            projects: projects,
            syntax: .todoist,
        )

        #expect(result.title == "Pedir #1 en la tienda")
        #expect(result.projectID == nil)
        #expect(result.tokens.isEmpty)
    }

    @Test
    func `removing tokens collapses the leftover whitespace`() {
        let result = QuickAddParser.parse(
            "  Comprar   leche   #Compras   p2  ",
            projects: projects,
            syntax: .todoist,
        )

        #expect(result.title == "Comprar leche")
        #expect(result.priority == .high)
    }

    @Test
    func `a title made only of shortcuts is empty`() {
        let result = QuickAddParser.parse("+Compras !3", projects: projects, syntax: .vikunja)

        #expect(result.title.isEmpty)
        #expect(result.projectID == 1)
        #expect(result.priority == .high)
    }

    @Test
    func `plain input passes through unchanged`() {
        let result = QuickAddParser.parse("Buy milk", projects: projects, syntax: .vikunja)

        #expect(result.title == "Buy milk")
        #expect(result.projectID == nil)
        #expect(result.priority == nil)
    }

    @Test
    func `with shortcuts off the title only loses its outer whitespace`() {
        let input = "  Leche  #Compras !3 @casa  "
        let result = QuickAddParser.parse(input, projects: projects, syntax: nil)

        #expect(result.title == "Leche  #Compras !3 @casa")
        #expect(result.tokens.isEmpty)
        #expect(result.projectID == nil)
        #expect(result.priority == nil)
        #expect(QuickAddParser.tokenize(input, syntax: nil).isEmpty)
    }
}
