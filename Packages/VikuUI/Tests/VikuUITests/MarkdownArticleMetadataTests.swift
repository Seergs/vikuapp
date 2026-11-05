import Testing
@testable import VikuUI

struct MarkdownArticleMetadataTests {
    @Test(arguments: [(0, 0), (1, 1), (199, 1), (200, 1), (201, 2), (400, 2), (401, 3)])
    func `reading time rounds up at 200 words per minute`(words: Int, minutes: Int) {
        let markdown = Array(repeating: "word", count: words).joined(separator: " ")
        let metadata = MarkdownArticleMetadata(markdown: markdown)
        #expect(metadata.wordCount == words)
        #expect(metadata.estimatedReadingMinutes == minutes)
    }

    @Test
    func `counts visible words rather than link URLs and Markdown syntax`() {
        let metadata = MarkdownArticleMetadata(markdown: """
        **Read** [this guide](https://example.com/a/very/long/hidden/path).

        ---

        Sigue sin conexión.
        """)
        #expect(metadata.wordCount == 6)
    }

    @Test
    func `inline formatting does not split words or join separate blocks`() {
        let metadata = MarkdownArticleMetadata(markdown: "un**break**able\n\nword")
        #expect(metadata.wordCount == 2)
    }

    @Test
    func `extracts heading order levels and visible inline text`() {
        let metadata = MarkdownArticleMetadata(markdown: """
        ## First **section**

        #### A [linked](https://example.com) heading

        ### Final `section`
        """)
        #expect(metadata.tableOfContents.map(\.title) == ["First section", "A linked heading", "Final section"])
        #expect(metadata.tableOfContents.map(\.level) == [2, 4, 3])
    }

    @Test
    func `navigation anchors match rendered headings with accents and punctuation`() {
        let metadata = MarkdownArticleMetadata(markdown: """
        ## ¿Qué puedes hacer?
        ## Antes de quedarte sin **conexión**
        ## A - B - C
        ## What's this?
        """)
        #expect(metadata.tableOfContents.map(\.anchor) == [
            "qué-puedes-hacer", "antes-de-quedarte-sin-conexión", "a-b-c", "whats-this",
        ])
    }

    @Test
    func `repeated headings have distinct deterministic identities`() {
        let source = "## Section\n\nText\n\n## Section"
        let first = MarkdownArticleMetadata(markdown: source).tableOfContents
        let second = MarkdownArticleMetadata(markdown: source).tableOfContents
        #expect(first.map(\.title) == ["Section", "Section"])
        #expect(Set(first.map(\.id)).count == 2)
        #expect(first == second)
    }

    @Test
    func `ignores heading syntax inside code blocks`() {
        let metadata = MarkdownArticleMetadata(markdown: """
        ```markdown
        # Not a heading
        ```

            ## Also code

        ## Real heading
        """)
        #expect(metadata.tableOfContents.map(\.title) == ["Real heading"])
    }

    @Test
    func `recognizes Setext headings through the Markdown parser`() {
        let metadata = MarkdownArticleMetadata(markdown: "Section\n-------\n\nBody")
        #expect(metadata.tableOfContents.map(\.title) == ["Section"])
        #expect(metadata.tableOfContents.map(\.level) == [2])
    }

    @Test
    func `displayed article metadata excludes the omitted title`() {
        let body = MarkdownArticleBody.removingLeadingHeading(from: "# Article title\n\n## Section\n\nBody")
        let metadata = MarkdownArticleMetadata(markdown: body)
        #expect(metadata.wordCount == 2)
        #expect(metadata.tableOfContents.map(\.title) == ["Section"])
    }

    @Test
    func `empty Markdown has no reading time or contents`() {
        let metadata = MarkdownArticleMetadata(markdown: " \n\n")
        #expect(metadata.wordCount == 0)
        #expect(metadata.estimatedReadingMinutes == 0)
        #expect(metadata.tableOfContents.isEmpty)
    }
}
