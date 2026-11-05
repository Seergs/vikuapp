/// Prepares an article for a screen that already supplies its title.
public enum MarkdownArticleBody {
    /// Omits a leading ATX level-one heading and surrounding blank lines.
    /// Later headings, code blocks, and documents without a leading title
    /// remain intact. The stored Markdown is never modified.
    public static func removingLeadingHeading(from markdown: String) -> String {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let titleIndex = lines.firstIndex(where: { !$0.allSatisfy(\.isWhitespace) }) else {
            return markdown
        }

        let line = lines[titleIndex]
        let indentation = line.prefix(while: { $0 == " " }).count
        // Four spaces introduce a code block, rather than a Markdown heading.
        guard indentation <= 3 else { return markdown }
        let heading = line.dropFirst(indentation)
        guard heading.first == "#" else { return markdown }
        let title = heading.dropFirst()
        guard title.isEmpty || title.first == " " || title.first == "\t" else {
            return markdown
        }

        guard let body = lines.dropFirst(titleIndex + 1).first(where: { !$0.allSatisfy(\.isWhitespace) }) else {
            return ""
        }
        return String(markdown[body.startIndex...])
    }
}
