import SwiftUI
import Textual
import VikuDesignSystem

/// Renders caller-supplied, already-localized Markdown without owning scrolling
/// or navigation. File loading and article selection belong to the caller.
struct MarkdownContentView: View {
    let markdown: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        let style = VikuMarkdownStyle(palette: palette)

        StructuredText(markdown: markdown)
            .textual.structuredTextStyle(style)
            .textual.highlighterTheme(style.highlighterTheme)
            .textual.textSelection(.enabled)
            .font(VikuFont.body)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.brand)
    }
}
