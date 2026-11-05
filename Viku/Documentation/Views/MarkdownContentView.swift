import SwiftUI
import Textual
import VikuDesignSystem
import VikuUI

/// Renders caller-supplied, already-localized Markdown without owning scrolling
/// or navigation. File loading and article selection belong to the caller.
struct MarkdownContentView: View {
    private let sections: [MarkdownAlertParser.Section]

    init(markdown: String) {
        self.sections = MarkdownAlertParser.sections(in: markdown)
    }

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        let style = VikuMarkdownStyle(palette: palette)

        VStack(alignment: .leading, spacing: VikuSpacing.md) {
            ForEach(sections.indices, id: \.self) { index in
                switch sections[index] {
                case let .markdown(content):
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        StructuredText(markdown: content)
                    }
                case let .alert(kind, content):
                    MarkdownAlertView(kind: kind, markdown: content)
                }
            }
        }
        .textual.structuredTextStyle(style)
        .textual.highlighterTheme(style.highlighterTheme)
        .textual.textSelection(.enabled)
        .font(VikuFont.body)
        .foregroundStyle(palette.textPrimary)
        .tint(palette.brand)
    }
}

private struct MarkdownAlertView: View {
    let kind: MarkdownAlertParser.Kind
    let markdown: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            .font(VikuFont.subheadline.weight(.semibold))
            .foregroundStyle(accent)

            StructuredText(markdown: markdown)
                .textual.structuredTextStyle(VikuMarkdownStyle(palette: palette, bodyFont: VikuFont.subheadline))
                .font(VikuFont.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VikuSpacing.md)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }

    private var title: String {
        switch kind {
        case .note: String(localized: "documentation.alert.note")
        case .tip: String(localized: "documentation.alert.tip")
        case .important: String(localized: "documentation.alert.important")
        case .warning: String(localized: "documentation.alert.warning")
        case .caution: String(localized: "documentation.alert.caution")
        }
    }

    private var symbol: String {
        switch kind {
        case .note: "info.circle"
        case .tip: "lightbulb"
        case .important: "exclamationmark.bubble"
        case .warning: "exclamationmark.triangle"
        case .caution: "hand.raised"
        }
    }

    private var accent: Color {
        switch kind {
        case .note, .important: palette.brand
        case .tip: palette.semanticSuccessText
        case .warning, .caution: palette.semanticDangerText
        }
    }
}

#Preview("Documentation alerts") {
    ScrollView {
        MarkdownContentView(markdown: """
        ## Dependencies

        > [!TIP]
        > Long press a task and drag it onto another to create a **dependency**.
        >
        > - Works from the task list.
        > - No need to open the detail.

        > [!NOTE]
        > Your changes are saved locally.

        > [!IMPORTANT]
        > Check the direction of the dependency.

        > [!WARNING]
        > This action affects other tasks.

        > [!CAUTION]
        > Review the changes before continuing.

        > An ordinary quote remains an ordinary quote.
        """)
        .padding(VikuSpacing.md)
    }
}
