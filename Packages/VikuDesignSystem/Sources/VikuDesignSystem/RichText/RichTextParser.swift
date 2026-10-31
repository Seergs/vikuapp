import Foundation

/// Turns a Vikunja rich-text HTML string into `[RichTextBlock]`.
///
/// Vikunja's web editor stores descriptions and comments as HTML, not
/// Markdown; this is the one place that knows that HTML's shape. The parser is
/// forgiving: unrecognized tags are transparent (their children still render),
/// unclosed tags close at their parent's end, and non-text content (images,
/// tables) collapses to its text.
public enum RichText {
    /// Parses `html` into renderable blocks. Returns `[]` for empty or
    /// whitespace-only input (including the editor's `<p></p>` "empty" value).
    public static func parse(_ html: String) -> [RichTextBlock] {
        let tokens = HTMLTokenizer.tokenize(html)
        var builder = TreeBuilder(tokens: tokens)
        let blocks = builder.parseBlocks(until: [])
        return blocks.filter { !$0.isEffectivelyEmpty }
    }

    /// Whether `html` has no visible content. Used to decide between showing a
    /// rendered description and an "Add description..." placeholder.
    public static func isEmpty(_ html: String) -> Bool {
        parse(html).isEmpty
    }

    /// A plain-text flattening, for prefilling an edit field or copying a task.
    /// Blocks are separated by blank lines; list items get a `• ` / `1. `
    /// prefix.
    public static func plainText(from html: String) -> String {
        plainText(from: parse(html))
    }

    /// Visible text for an already parsed document or list item.
    public static func plainText(from blocks: [RichTextBlock]) -> String {
        blocks.map { plainText(for: $0) }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainText(for block: RichTextBlock) -> String {
        switch block {
        case let .paragraph(runs), let .heading(_, runs):
            runs.map(\.text).joined()
        case let .bulletList(items):
            items.map { "• " + plainText(forItemBlocks: $0.content) }.joined(separator: "\n")
        case let .orderedList(start, items):
            items.enumerated()
                .map { "\(start + $0.offset). " + plainText(forItemBlocks: $0.element.content) }
                .joined(separator: "\n")
        case let .taskList(items):
            items.map {
                ($0.isChecked ? "[x] " : "[ ] ") + plainText(forItemBlocks: $0.content)
            }.joined(separator: "\n")
        case let .blockquote(blocks):
            blocks.map { plainText(for: $0) }.joined(separator: "\n")
        case let .codeBlock(text, _):
            text
        case .thematicBreak:
            "---"
        }
    }

    private static func plainText(forItemBlocks blocks: [RichTextBlock]) -> String {
        blocks.map { plainText(for: $0) }.joined(separator: " ")
    }
}

private extension RichTextBlock {
    /// A paragraph/heading with no text, and no runs, contributes nothing.
    var isEffectivelyEmpty: Bool {
        switch self {
        case let .paragraph(runs), let .heading(_, runs):
            runs.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case let .bulletList(items):
            items.isEmpty
        case let .orderedList(_, items):
            items.isEmpty
        case let .taskList(items):
            items.isEmpty
        case let .blockquote(blocks):
            blocks.allSatisfy(\.isEffectivelyEmpty)
        case .codeBlock, .thematicBreak:
            false
        }
    }
}

/// Walks the token stream once, tracking position in `index`. Not reusable
/// across parses.
private struct TreeBuilder {
    let tokens: [HTMLToken]
    var index = 0

    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "blockquote", "pre", "hr",
    ]
    /// Elements whose entire subtree is skipped (the checkbox markup inside a
    /// TipTap task item).
    private static let skippedSubtreeTags: Set<String> = ["label", "input"]

    // MARK: Blocks

    mutating func parseBlocks(until stoppers: Set<String>) -> [RichTextBlock] {
        var blocks: [RichTextBlock] = []

        while index < tokens.count {
            switch tokens[index] {
            case let .endTag(name):
                if stoppers.contains(name) {
                    return blocks
                }
                index += 1 // stray close tag, ignore

            case let .text(value):
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    index += 1
                } else {
                    blocks.append(.paragraph(parseInline()))
                }

            case let .startTag(name, attributes, selfClosing):
                if Self.skippedSubtreeTags.contains(name) {
                    skipSubtree(name, selfClosing: selfClosing)
                } else if name == "br" {
                    index += 1 // a lone <br> between blocks is just spacing
                } else if name == "hr" {
                    blocks.append(.thematicBreak)
                    index += 1
                } else if Self.blockTags.contains(name) {
                    blocks.append(contentsOf: parseBlockElement(name, attributes: attributes))
                } else {
                    // Unknown or inline element at block level: an implicit
                    // paragraph starts here.
                    blocks.append(.paragraph(parseInline()))
                }
            }
        }

        return blocks
    }

    private mutating func parseBlockElement(
        _ name: String,
        attributes: [String: String],
    ) -> [RichTextBlock] {
        switch name {
        case "p":
            index += 1
            let runs = parseInline()
            consumeEndTag("p")
            return [.paragraph(runs)]

        case "div":
            // TipTap wraps task-item content in a bare <div>; treat it as a
            // transparent block container.
            index += 1
            let inner = parseBlocks(until: ["div"])
            consumeEndTag("div")
            return inner.isEmpty ? [] : inner

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(name.dropFirst()) ?? 1
            index += 1
            let runs = parseInline()
            consumeEndTag(name)
            return [.heading(level: level, runs)]

        case "blockquote":
            index += 1
            let inner = parseBlocks(until: ["blockquote"])
            consumeEndTag("blockquote")
            return [.blockquote(inner)]

        case "pre":
            index += 1
            let (text, language) = parseCodeBlock()
            consumeEndTag("pre")
            return [.codeBlock(text: text, language: language)]

        case "ul":
            index += 1
            let isTaskList = attributes["data-type"] == "taskList"
            if isTaskList {
                let items = parseTaskItems()
                consumeEndTag("ul")
                return [.taskList(items)]
            }
            let items = parseListItems(listTag: "ul")
            consumeEndTag("ul")
            return [.bulletList(items)]

        case "ol":
            index += 1
            let start = attributes["start"].flatMap(Int.init) ?? 1
            let items = parseListItems(listTag: "ol")
            consumeEndTag("ol")
            return [.orderedList(start: start, items)]

        default:
            index += 1
            return []
        }
    }

    private mutating func parseListItems(listTag: String) -> [RichTextListItem] {
        var items: [RichTextListItem] = []

        while index < tokens.count {
            switch tokens[index] {
            case let .endTag(name) where name == listTag:
                return items
            case .startTag(name: "li", _, _):
                index += 1
                let content = parseBlocks(until: ["li"])
                consumeEndTag("li")
                items.append(RichTextListItem(content: normalizeItemContent(content)))
            case let .endTag(name):
                if name == "li" {
                    index += 1
                } else {
                    return items
                }
            default:
                index += 1 // whitespace or stray markup between <li>s
            }
        }

        return items
    }

    private mutating func parseTaskItems() -> [RichTextTaskItem] {
        var items: [RichTextTaskItem] = []

        while index < tokens.count {
            switch tokens[index] {
            case .endTag(name: "ul"):
                return items
            case let .startTag(name: "li", attributes, _):
                let isChecked = attributes["data-checked"] == "true"
                let sourceTokenIndex = index
                index += 1
                let content = parseBlocks(until: ["li"])
                consumeEndTag("li")
                items.append(
                    RichTextTaskItem(
                        isChecked: isChecked,
                        content: normalizeItemContent(content),
                        sourceTokenIndex: sourceTokenIndex,
                    ),
                )
            case let .endTag(name):
                if name == "li" {
                    index += 1
                } else {
                    return items
                }
            default:
                index += 1
            }
        }

        return items
    }

    /// A list item with a single paragraph is the common case; keep it as-is.
    /// An empty item still needs a paragraph so it renders a bullet.
    private func normalizeItemContent(_ blocks: [RichTextBlock]) -> [RichTextBlock] {
        blocks.isEmpty ? [.paragraph([])] : blocks
    }

    /// `<pre>` content is raw: collect every text token, ignore inline tags,
    /// pull an optional language off the inner `<code class="language-xx">`.
    private mutating func parseCodeBlock() -> (text: String, language: String?) {
        var text = ""
        var language: String?

        while index < tokens.count {
            switch tokens[index] {
            case .endTag(name: "pre"):
                return (text.trimmingCharacters(in: .newlines), language)
            case let .startTag(name: "code", attributes, _):
                if let className = attributes["class"],
                   let range = className.range(of: "language-") {
                    language = String(className[range.upperBound...])
                        .split(separator: " ").first.map(String.init)
                } else if let explicit = attributes["data-language"], !explicit.isEmpty {
                    language = explicit
                }
                index += 1
            case let .text(value):
                text += value
                index += 1
            default:
                index += 1
            }
        }

        return (text.trimmingCharacters(in: .newlines), language)
    }

    // MARK: Inline

    private mutating func parseInline() -> [RichTextRun] {
        var accumulator = RunAccumulator()
        appendInline(into: &accumulator, styles: [], link: nil)
        return accumulator.runs
    }

    private mutating func appendInline(
        into accumulator: inout RunAccumulator,
        styles: RichTextInlineStyle,
        link: String?,
    ) {
        while index < tokens.count {
            switch tokens[index] {
            case let .text(value):
                accumulator.append(value, styles: styles, link: link)
                index += 1

            case let .endTag(name):
                // A close tag ends this inline context regardless of which tag
                // it is: `stoppers` (the enclosing block) or a wrapper we
                // opened. Either way the caller unwinds.
                _ = name
                return

            case let .startTag(name, attributes, selfClosing):
                if name == "br" {
                    accumulator.append("\n", styles: styles, link: link)
                    index += 1
                } else if Self.blockTags.contains(name) {
                    // A block-level tag started mid-paragraph: stop the inline
                    // run so `parseBlocks` can pick the block up.
                    return
                } else if Self.skippedSubtreeTags.contains(name) {
                    skipSubtree(name, selfClosing: selfClosing)
                } else if selfClosing {
                    index += 1
                } else {
                    let childStyles = styles.union(Self.inlineStyle(for: name))
                    let childLink = name == "a" ? (attributes["href"] ?? link) : link
                    index += 1
                    appendInline(into: &accumulator, styles: childStyles, link: childLink)
                    consumeEndTag(name)
                }
            }
        }
    }

    private static func inlineStyle(for tag: String) -> RichTextInlineStyle {
        switch tag {
        case "strong", "b": .bold
        case "em", "i": .italic
        case "s", "strike", "del": .strikethrough
        case "code": .code
        default: []
        }
    }

    // MARK: Helpers

    private mutating func consumeEndTag(_ name: String) {
        if index < tokens.count, case let .endTag(closed) = tokens[index], closed == name {
            index += 1
        }
    }

    /// Advances past a subtree whose content is irrelevant (the checkbox markup
    /// in a task item). Handles nesting of the same tag.
    private mutating func skipSubtree(_ name: String, selfClosing: Bool) {
        index += 1
        if selfClosing {
            return
        }
        var depth = 1
        while index < tokens.count, depth > 0 {
            switch tokens[index] {
            case let .startTag(inner, _, innerSelfClosing) where inner == name:
                if !innerSelfClosing {
                    depth += 1
                }
            case let .endTag(inner) where inner == name:
                depth -= 1
            default:
                break
            }
            index += 1
        }
    }
}

/// Coalesces consecutive text with identical styling into one `RichTextRun`.
private struct RunAccumulator {
    private(set) var runs: [RichTextRun] = []

    mutating func append(_ text: String, styles: RichTextInlineStyle, link: String?) {
        guard !text.isEmpty else { return }
        if var last = runs.last, last.styles == styles, last.link == link {
            last.text += text
            runs[runs.count - 1] = last
        } else {
            runs.append(RichTextRun(text: text, styles: styles, link: link))
        }
    }
}
