import Testing
@testable import VikuUI

struct MarkdownAlertParserTests {
    @Test(arguments: MarkdownAlertParser.Kind.allCases)
    func `recognizes each supported alert and removes only the quote prefix`(_ kind: MarkdownAlertParser.Kind) {
        let source = "> [!\(kind.rawValue)]\n> Use **bold** and [links](https://vikunja.io).\n>\n> - First\n> - Second"
        #expect(MarkdownAlertParser.sections(in: source) == [
            .alert(kind, "Use **bold** and [links](https://vikunja.io).\n\n- First\n- Second"),
        ])
    }

    @Test
    func `preserves surrounding Markdown and separates consecutive alerts`() {
        let source = "## Before\n\n> [!TIP]\n> First\n\n> [!NOTE]\n> Second\n\n## After"
        #expect(MarkdownAlertParser.sections(in: source) == [
            .markdown("## Before\n"),
            .alert(.tip, "First"),
            .markdown(""),
            .alert(.note, "Second"),
            .markdown("\n## After"),
        ])
    }

    @Test(arguments: [
        "> Ordinary quote\n> More text",
        "> [!UNKNOWN]\n> Body",
        "> [!tip]\n> Body",
        "> [!TIP] custom title\n> Body",
        "> [!TIP]",
        "> [!TIP]\n>\n>   ",
        "Paragraph\n> [!TIP]\n> Body",
        "- List\n\n  > [!TIP]\n  > Body",
        "> > [!TIP]\n> > Body",
        "    > [!TIP]\n    > Body",
    ])
    func `leaves ordinary quotes and unsupported syntax unchanged`(_ source: String) {
        #expect(MarkdownAlertParser.sections(in: source) == [.markdown(source)])
    }

    @Test(arguments: ["```", "~~~~", "   ```markdown"])
    func `does not interpret alert examples inside fenced code`(_ opening: String) {
        let closing = opening.contains("~") ? "~~~~" : "```"
        let source = "\(opening)\n\n> [!TIP]\n> Example\n\(closing)\n\n> [!TIP]\n> Real tip"
        #expect(MarkdownAlertParser.sections(in: source) == [
            .markdown("\(opening)\n\n> [!TIP]\n> Example\n\(closing)\n"),
            .alert(.tip, "Real tip"),
        ])
    }

    @Test
    func `shorter fences and fences with trailing text do not close code`() {
        let source = "````\n```\n```` not a closing fence\n\n> [!TIP]\n> Still code"
        #expect(MarkdownAlertParser.sections(in: source) == [.markdown(source)])
    }

    @Test
    func `accepts Windows line endings`() {
        #expect(MarkdownAlertParser.sections(in: "> [!TIP]\r\n> Body\r\n>\r\n> More") == [
            .alert(.tip, "Body\n\nMore"),
        ])
    }

    @Test
    func `does not recursively parse the alert body`() {
        #expect(MarkdownAlertParser.sections(in: "> [!NOTE]\n> > [!TIP]\n> > Quoted example") == [
            .alert(.note, "> [!TIP]\n> Quoted example"),
        ])
    }
}
