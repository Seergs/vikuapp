import Testing
@testable import VikuDesignSystem

@Suite("RichText.parse")
struct RichTextParserTests {
    @Test
    func `parses a plain paragraph`() {
        let blocks = RichText.parse("<p>Hello world</p>")
        #expect(blocks == [.paragraph([RichTextRun(text: "Hello world")])])
    }

    @Test
    func `treats the editor's empty value as no content`() {
        #expect(RichText.parse("<p></p>").isEmpty)
        #expect(RichText.parse("").isEmpty)
        #expect(RichText.parse("   \n  ").isEmpty)
        #expect(RichText.isEmpty("<p><br></p>"))
    }

    @Test
    func `wraps bare text in an implicit paragraph`() {
        let blocks = RichText.parse("just text")
        #expect(blocks == [.paragraph([RichTextRun(text: "just text")])])
    }

    @Test
    func `merges nested inline styling onto one run`() {
        let blocks = RichText.parse("<p><strong><em>bold italic</em></strong></p>")
        #expect(blocks == [
            .paragraph([RichTextRun(text: "bold italic", styles: [.bold, .italic])]),
        ])
    }

    @Test
    func `splits a paragraph into styled and unstyled runs`() {
        let blocks = RichText.parse("<p>a <strong>b</strong> c</p>")
        #expect(blocks == [
            .paragraph([
                RichTextRun(text: "a "),
                RichTextRun(text: "b", styles: .bold),
                RichTextRun(text: " c"),
            ]),
        ])
    }

    @Test
    func `maps b i s del tags onto styles`() {
        let blocks = RichText.parse("<p><b>x</b> <i>y</i> <s>z</s> <del>w</del> <code>c</code></p>")
        #expect(blocks == [
            .paragraph([
                RichTextRun(text: "x", styles: .bold),
                RichTextRun(text: " "),
                RichTextRun(text: "y", styles: .italic),
                RichTextRun(text: " "),
                RichTextRun(text: "z", styles: .strikethrough),
                RichTextRun(text: " "),
                RichTextRun(text: "w", styles: .strikethrough),
                RichTextRun(text: " "),
                RichTextRun(text: "c", styles: .code),
            ]),
        ])
    }

    @Test
    func `coalesces adjacent runs that share styling`() {
        let blocks = RichText.parse("<p><s>a</s><del>b</del></p>")
        #expect(blocks == [.paragraph([RichTextRun(text: "ab", styles: .strikethrough)])])
    }

    @Test
    func `carries a link href onto its runs`() {
        let blocks = RichText.parse(#"<p>see <a href="https://vikunja.io">the site</a></p>"#)
        #expect(blocks == [
            .paragraph([
                RichTextRun(text: "see "),
                RichTextRun(text: "the site", link: "https://vikunja.io"),
            ]),
        ])
    }

    @Test
    func `turns a br into a newline within a run`() {
        let blocks = RichText.parse("<p>line one<br>line two</p>")
        #expect(blocks == [.paragraph([RichTextRun(text: "line one\nline two")])])
    }

    @Test
    func `parses headings and clamps the level from the tag`() {
        let blocks = RichText.parse("<h1>Title</h1><h3>Sub</h3>")
        #expect(blocks == [
            .heading(level: 1, [RichTextRun(text: "Title")]),
            .heading(level: 3, [RichTextRun(text: "Sub")]),
        ])
    }

    @Test
    func `parses a bullet list`() {
        let blocks = RichText.parse("<ul><li>one</li><li>two</li></ul>")
        #expect(blocks == [
            .bulletList([
                RichTextListItem(content: [.paragraph([RichTextRun(text: "one")])]),
                RichTextListItem(content: [.paragraph([RichTextRun(text: "two")])]),
            ]),
        ])
    }

    @Test
    func `parses an ordered list with a custom start`() {
        let blocks = RichText.parse(#"<ol start="3"><li>c</li><li>d</li></ol>"#)
        #expect(blocks == [
            .orderedList(start: 3, [
                RichTextListItem(content: [.paragraph([RichTextRun(text: "c")])]),
                RichTextListItem(content: [.paragraph([RichTextRun(text: "d")])]),
            ]),
        ])
    }

    @Test
    func `nests a sub-list inside a list item`() {
        let blocks = RichText.parse("<ul><li>parent<ul><li>child</li></ul></li></ul>")
        #expect(blocks == [
            .bulletList([
                RichTextListItem(content: [
                    .paragraph([RichTextRun(text: "parent")]),
                    .bulletList([
                        RichTextListItem(content: [.paragraph([RichTextRun(text: "child")])]),
                    ]),
                ]),
            ]),
        ])
    }

    @Test
    func `parses a TipTap task list with checkbox state`() {
        let checked = #"<li data-checked="true" data-type="taskItem">"#
            + "<label><input type=\"checkbox\" checked><span></span></label><div><p>done</p></div></li>"
        let unchecked = #"<li data-checked="false" data-type="taskItem">"#
            + "<label><input type=\"checkbox\"><span></span></label><div><p>todo</p></div></li>"
        let html = #"<ul data-type="taskList">\#(checked)\#(unchecked)</ul>"#
        let blocks = RichText.parse(html)
        #expect(blocks == [
            .taskList([
                RichTextTaskItem(
                    isChecked: true, content: [.paragraph([RichTextRun(text: "done")])], sourceTokenIndex: 1,
                ),
                RichTextTaskItem(
                    isChecked: false, content: [.paragraph([RichTextRun(text: "todo")])], sourceTokenIndex: 13,
                ),
            ]),
        ])
    }

    @Test
    func `parses a blockquote containing paragraphs`() {
        let blocks = RichText.parse("<blockquote><p>quoted</p></blockquote>")
        #expect(blocks == [.blockquote([.paragraph([RichTextRun(text: "quoted")])])])
    }

    @Test
    func `parses a code block and pulls the language from the class`() {
        let blocks = RichText.parse(#"<pre><code class="language-swift">let x = 1</code></pre>"#)
        #expect(blocks == [.codeBlock(text: "let x = 1", language: "swift")])
    }

    @Test
    func `keeps raw angle brackets inside a code block`() {
        let blocks = RichText.parse("<pre><code>a &lt; b &amp;&amp; c &gt; d</code></pre>")
        #expect(blocks == [.codeBlock(text: "a < b && c > d", language: nil)])
    }

    @Test
    func `parses a horizontal rule`() {
        let blocks = RichText.parse("<p>above</p><hr><p>below</p>")
        #expect(blocks == [
            .paragraph([RichTextRun(text: "above")]),
            .thematicBreak,
            .paragraph([RichTextRun(text: "below")]),
        ])
    }

    @Test
    func `decodes named and numeric entities in text`() {
        let blocks = RichText.parse("<p>a &amp; b &lt; c &#39;d&#39; &#x263A;</p>")
        #expect(blocks == [.paragraph([RichTextRun(text: "a & b < c 'd' \u{263A}")])])
    }

    @Test
    func `reduces an unknown element to its text content`() {
        let blocks = RichText.parse("<p>before <img src=\"x.png\" alt=\"pic\"> <mark>after</mark></p>")
        #expect(blocks == [
            .paragraph([RichTextRun(text: "before  after")]),
        ])
    }

    @Test
    func `survives an unclosed tag`() {
        let blocks = RichText.parse("<p>text with <strong>unclosed bold")
        #expect(blocks == [
            .paragraph([
                RichTextRun(text: "text with "),
                RichTextRun(text: "unclosed bold", styles: .bold),
            ]),
        ])
    }

    @Test
    func `ignores html comments`() {
        let blocks = RichText.parse("<p>visible<!-- hidden --> text</p>")
        #expect(blocks == [.paragraph([RichTextRun(text: "visible text")])])
    }
}

@Suite("RichText.plainText")
struct RichTextPlainTextTests {
    @Test
    func `flattens paragraphs with blank-line separators`() {
        let text = RichText.plainText(from: "<p>first</p><p>second</p>")
        #expect(text == "first\n\nsecond")
    }

    @Test
    func `prefixes list items`() {
        let text = RichText.plainText(from: "<ul><li>a</li><li>b</li></ul>")
        #expect(text == "• a\n• b")
    }

    @Test
    func `renders task item checkbox state`() {
        let item = #"<li data-checked="true" data-type="taskItem"><div><p>x</p></div></li>"#
        let html = #"<ul data-type="taskList">\#(item)</ul>"#
        #expect(RichText.plainText(from: html) == "[x] x")
    }

    @Test
    func `strips inline markup`() {
        let text = RichText.plainText(from: "<p>a <strong>bold</strong> <a href=\"x\">link</a></p>")
        #expect(text == "a bold link")
    }
}
