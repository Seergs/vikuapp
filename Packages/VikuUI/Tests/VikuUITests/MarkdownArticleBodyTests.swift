import Testing
@testable import VikuUI

struct MarkdownArticleBodyTests {
    @Test
    func `omits the article title while preserving the remaining Markdown`() {
        let body = "A **paragraph**.\n\n## Section\n\n- Item\n\n# Later heading\n"
        let source = "# Article\n\n" + body

        #expect(MarkdownArticleBody.removingLeadingHeading(from: source) == body)
    }

    @Test(arguments: ["# Article", " # Article", "  # Article", "   # Article", "#\tArticle", "# Article #"])
    func `recognizes valid leading level one headings`(heading: String) {
        #expect(MarkdownArticleBody.removingLeadingHeading(from: heading + "\n\nBody") == "Body")
    }

    @Test
    func `handles leading blank lines and preserves Windows line endings`() {
        let source = "\r\n  \r\n# Article\r\n\r\nBody\r\n\r\n## Section\r\n"
        #expect(MarkdownArticleBody.removingLeadingHeading(from: source) == "Body\r\n\r\n## Section\r\n")
    }

    @Test(arguments: [
        "Body\n\n# Later heading",
        "## Section\n\nBody",
        "### Subsection\n\nBody",
        "```markdown\n# Example\n```",
        "    # Indented code",
        "\t# Indented code",
        "\\# Literal hash",
        "#hashtag",
        "Title\n=====\n\nBody",
        "",
        " \n\t\n",
    ])
    func `preserves documents without a leading ATX title`(source: String) {
        #expect(MarkdownArticleBody.removingLeadingHeading(from: source) == source)
    }

    @Test(arguments: ["# Article", "# Article\n\n", "#\n"])
    func `title only documents have an empty body`(source: String) {
        #expect(MarkdownArticleBody.removingLeadingHeading(from: source).isEmpty)
    }
}
