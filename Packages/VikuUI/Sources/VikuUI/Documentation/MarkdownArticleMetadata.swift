import Foundation

/// Derived from the same Foundation Markdown representation that Textual uses.
/// All metadata is local and can be prepared before presenting an article.
public struct MarkdownArticleMetadata: Sendable {
    private static let wordsPerMinute = 200

    public struct Heading: Identifiable, Equatable, Sendable {
        /// Foundation's block identity distinguishes repeated heading titles.
        public let id: Int
        public let title: String
        public let level: Int

        /// Heading ID assigned by the pinned Textual renderer. Keep the
        /// original letters and accents; punctuation is omitted from anchors.
        public var anchor: String {
            String(
                title.lowercased()
                    .map { $0.isWhitespace ? "-" : $0 }
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    .split(separator: "-", omittingEmptySubsequences: true)
                    .joined(separator: "-"),
            )
        }
    }

    public let wordCount: Int
    public let estimatedReadingMinutes: Int
    public let tableOfContents: [Heading]

    /// Reading time is an approximation at 200 words per minute, rounded up.
    /// Count displayed text (including code), excluding Markdown syntax and
    /// link destinations. Empty content has no reading-time estimate.
    public init(markdown: String) {
        guard let parsed = try? AttributedString(markdown: markdown) else {
            self.wordCount = Self.countWords(in: markdown)
            self.estimatedReadingMinutes = Self.readingMinutes(for: wordCount)
            self.tableOfContents = []
            return
        }

        var blocks: [Int: String] = [:]
        var headings: [Int: String] = [:]
        var levels: [Int: Int] = [:]
        var headingOrder: [Int] = []

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let components = run.presentationIntent?.components ?? []
            // Preserve inline fragments within each block so `un**break**able`
            // counts as one word and adjacent paragraphs don't get joined.
            blocks[components.first?.identity ?? 0, default: ""] += text

            for component in components {
                guard case let .header(level) = component.kind else { continue }
                if headings[component.identity] == nil {
                    headingOrder.append(component.identity)
                    levels[component.identity] = level
                }
                headings[component.identity, default: ""] += text
            }
        }

        self.wordCount = blocks.values.reduce(0) { $0 + Self.countWords(in: $1) }
        self.estimatedReadingMinutes = Self.readingMinutes(for: wordCount)
        self.tableOfContents = headingOrder.compactMap { id in
            guard let title = headings[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, let level = levels[id]
            else { return nil }
            return Heading(id: id, title: title, level: level)
        }
    }

    private static func readingMinutes(for wordCount: Int) -> Int {
        (wordCount + wordsPerMinute - 1) / wordsPerMinute
    }

    private static func countWords(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
