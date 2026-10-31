import Foundation

// The parsed shape of a Vikunja rich-text field (task description, comment
// body). Vikunja stores these as the HTML output of its web editor
// (TipTap/ProseMirror), not Markdown, so `RichText.parse(_:)` turns that HTML
// into this small, renderer-agnostic tree. `RichTextView` walks it to draw
// native SwiftUI; the model itself carries no SwiftUI so it stays unit
// testable.
//
// The covered subset matches what the editor actually emits: paragraphs,
// headings, bold/italic/strikethrough/inline-code, links, bullet/ordered
// lists, task lists (optionally interactive checkboxes), blockquotes, code blocks and
// horizontal rules. Anything outside that (images, tables, embeds) is reduced
// to its text content rather than dropped.

/// One contiguous span of inline text sharing the same styling and link.
public struct RichTextRun: Equatable, Sendable {
    public var text: String
    public var styles: RichTextInlineStyle
    /// The `href` of the enclosing `<a>`, verbatim from the HTML. The renderer
    /// resolves it to a `URL`; kept as a string here so the model stays
    /// Foundation-only and an unparseable href is the renderer's problem.
    public var link: String?

    public init(text: String, styles: RichTextInlineStyle = [], link: String? = nil) {
        self.text = text
        self.styles = styles
        self.link = link
    }
}

/// Inline styling flags that can stack on a single run (bold + italic + link).
public struct RichTextInlineStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let bold = RichTextInlineStyle(rawValue: 1 << 0)
    public static let italic = RichTextInlineStyle(rawValue: 1 << 1)
    public static let strikethrough = RichTextInlineStyle(rawValue: 1 << 2)
    public static let code = RichTextInlineStyle(rawValue: 1 << 3)
}

/// A block-level element. `indirect` because blockquotes and list items nest
/// arbitrary blocks (a quote containing a list, a list item with sub-bullets).
public indirect enum RichTextBlock: Equatable, Sendable {
    case paragraph([RichTextRun])
    /// `level` is clamped to 1...6.
    case heading(level: Int, [RichTextRun])
    case bulletList([RichTextListItem])
    /// `start` is the first item's number (`<ol start="3">` → 3, default 1).
    case orderedList(start: Int, [RichTextListItem])
    case taskList([RichTextTaskItem])
    case blockquote([RichTextBlock])
    /// Raw, unescaped source text. `language` comes from a `language-xxx` class
    /// or `data-language` on the inner `<code>`, when present.
    case codeBlock(text: String, language: String?)
    case thematicBreak
}

public struct RichTextListItem: Equatable, Sendable {
    public var content: [RichTextBlock]
    public init(content: [RichTextBlock]) {
        self.content = content
    }
}

public struct RichTextTaskItem: Equatable, Sendable {
    /// Token position in the original HTML, valid only for that document.
    public var sourceTokenIndex: Int?
    public var isChecked: Bool
    public var content: [RichTextBlock]
    public init(isChecked: Bool, content: [RichTextBlock], sourceTokenIndex: Int? = nil) {
        self.sourceTokenIndex = sourceTokenIndex
        self.isChecked = isChecked
        self.content = content
    }
}
