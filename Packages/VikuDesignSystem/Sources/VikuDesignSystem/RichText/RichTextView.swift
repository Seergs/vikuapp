import SwiftUI

/// Renders a Vikunja rich-text field (a task description or comment body) as
/// native SwiftUI.
///
/// Vikunja stores these as HTML from its web editor; `RichText.parse(_:)` does
/// the HTML work and this view walks the resulting blocks. Text color is
/// inherited from the caller's `.foregroundStyle`; `baseFont` sets the
/// paragraph/list size and headings scale up from there.
///
/// The covered subset (paragraphs, headings, bold/italic/strikethrough/code,
/// links, lists, task lists, blockquotes, code blocks, rules) matches what the
/// editor emits. Images and tables collapse to their text.
public struct RichTextView: View {
    private let blocks: [RichTextBlock]
    private let baseFont: Font

    public init(html: String, baseFont: Font = VikuFont.callout) {
        self.init(blocks: RichText.parse(html), baseFont: baseFont)
    }

    public init(blocks: [RichTextBlock], baseFont: Font = VikuFont.callout) {
        self.blocks = blocks
        self.baseFont = baseFont
    }

    public var body: some View {
        RichTextBlocksView(blocks: blocks, baseFont: baseFont)
    }
}

/// A run of block-level nodes, stacked vertically. Reused for the top level and
/// for the contents of a blockquote or list item.
struct RichTextBlocksView: View {
    let blocks: [RichTextBlock]
    let baseFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                RichTextBlockView(block: block, baseFont: baseFont)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RichTextBlockView: View {
    let block: RichTextBlock
    let baseFont: Font

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        switch block {
        case let .paragraph(runs):
            Text(
                RichTextInline.attributedString(
                    runs,
                    baseFont: baseFont,
                    inlineCodeBackground: palette.fieldBackground,
                ),
            )
            .font(baseFont)
            .fixedSize(horizontal: false, vertical: true)

        case let .heading(level, runs):
            Text(
                RichTextInline.attributedString(
                    runs,
                    baseFont: headingFont(level),
                    inlineCodeBackground: palette.fieldBackground,
                ),
            )
            .font(headingFont(level))
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, VikuSpacing.xs)

        case let .bulletList(items):
            RichTextListView(markers: items.map { _ in "•" }, items: items.map(\.content), baseFont: baseFont)

        case let .orderedList(start, items):
            RichTextListView(
                markers: items.indices.map { "\(start + $0)." },
                items: items.map(\.content),
                baseFont: baseFont,
            )

        case let .taskList(items):
            RichTextTaskListView(items: items, baseFont: baseFont)

        case let .blockquote(inner):
            RichTextQuoteView(blocks: inner, baseFont: baseFont)

        case let .codeBlock(text, _):
            RichTextCodeBlockView(text: text)

        case .thematicBreak:
            Divider().padding(.vertical, VikuSpacing.xs)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: VikuFont.title2
        case 2: VikuFont.title3
        case 3: VikuFont.headline
        default: VikuFont.subheadline
        }
    }
}

// MARK: - Lists

private struct RichTextListView: View {
    let markers: [String]
    let items: [[RichTextBlock]]
    let baseFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, content in
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.sm) {
                    Text(markers[index])
                        .font(baseFont)
                        .foregroundStyle(VikuColor.textTertiary)
                        .frame(minWidth: VikuSpacing.md, alignment: .trailing)
                    RichTextBlocksView(blocks: content, baseFont: baseFont)
                }
            }
        }
    }
}

private struct RichTextTaskListView: View {
    let items: [RichTextTaskItem]
    let baseFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.sm) {
                    Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                        .font(baseFont)
                        .foregroundStyle(item.isChecked ? VikuColor.brandPrimary : VikuColor.textTertiary)
                    RichTextBlocksView(blocks: item.content, baseFont: baseFont)
                        .opacity(item.isChecked ? 0.6 : 1)
                }
            }
        }
    }
}

// MARK: - Blockquote

private struct RichTextQuoteView: View {
    let blocks: [RichTextBlock]
    let baseFont: Font

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(VikuColor.textTertiary)
                .frame(width: 3)
            RichTextBlocksView(blocks: blocks, baseFont: baseFont)
                .foregroundStyle(VikuColor.textTertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Code block

private struct RichTextCodeBlockView: View {
    let text: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.primary)
                .padding(VikuSpacing.sm)
        }
        .background(
            palette.fieldBackground,
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}

// MARK: - Inline runs

enum RichTextInline {
    /// Builds one `AttributedString` from a paragraph's runs, applying each
    /// run's styling and link. `baseFont` is only needed for the inline-code
    /// runs, which switch to a monospaced face of the same size.
    static func attributedString(_ runs: [RichTextRun], baseFont: Font, inlineCodeBackground: Color) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            result.append(attributed(run, baseFont: baseFont, inlineCodeBackground: inlineCodeBackground))
        }
        return result
    }

    private static func attributed(_ run: RichTextRun, baseFont: Font, inlineCodeBackground: Color) -> AttributedString {
        var piece = AttributedString(run.text)

        var intent: InlinePresentationIntent = []
        if run.styles.contains(.bold) {
            intent.insert(.stronglyEmphasized)
        }
        if run.styles.contains(.italic) {
            intent.insert(.emphasized)
        }
        if run.styles.contains(.strikethrough) {
            intent.insert(.strikethrough)
        }
        if !intent.isEmpty {
            piece.inlinePresentationIntent = intent
        }

        if run.styles.contains(.code) {
            piece.font = baseFont.monospaced()
            piece.backgroundColor = inlineCodeBackground
        }

        if let link = run.link, let url = URL(string: link.trimmingCharacters(in: .whitespaces)) {
            piece.link = url
        }

        return piece
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rich text") {
    ScrollView {
        RichTextView(html: """
        <h1>Release checklist</h1>
        <p>The <strong>big</strong> items before we <em>ship</em>, see the
        <a href="https://vikunja.io">docs</a>.</p>
        <ul>
          <li>Bump the version</li>
          <li>Update the changelog<ul><li>group by area</li></ul></li>
        </ul>
        <ul data-type="taskList">
          <li data-checked="true" data-type="taskItem"><div><p>Freeze the branch</p></div></li>
          <li data-checked="false" data-type="taskItem"><div><p>Tag the build</p></div></li>
        </ul>
        <blockquote><p>Remember to notify the community first.</p></blockquote>
        <pre><code class="language-swift">let version = "1.2.0"</code></pre>
        <hr>
        <p>Ping <code>@release-team</code> when done.</p>
        """)
        .foregroundStyle(VikuColor.textSecondary)
        .padding()
    }
}
#endif
