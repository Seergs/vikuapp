import SwiftUI
import Textual
import VikuDesignSystem

/// Adapts Textual's blocks to Viku without adding a Textual dependency to the
/// design system packages. Font tokens retain their native Dynamic Type sizes.
struct VikuMarkdownStyle: StructuredText.Style {
    let palette: VikuPalette

    var inlineStyle: InlineStyle {
        InlineStyle()
            .code(.monospaced, .backgroundColor(palette.fieldBackground))
            .strong(.fontWeight(.bold))
            .link(.foregroundColor(palette.brand), .underlineStyle(.single))
    }

    var headingStyle: some StructuredText.HeadingStyle {
        VikuMarkdownHeadingStyle()
    }

    var paragraphStyle: some StructuredText.ParagraphStyle {
        VikuMarkdownParagraphStyle()
    }

    var blockQuoteStyle: some StructuredText.BlockQuoteStyle {
        VikuMarkdownQuoteStyle(palette: palette)
    }

    var codeBlockStyle: some StructuredText.CodeBlockStyle {
        VikuMarkdownCodeStyle(palette: palette)
    }

    var listItemStyle: some StructuredText.ListItemStyle {
        VikuMarkdownListItemStyle()
    }

    var unorderedListMarker: some StructuredText.UnorderedListMarker {
        .hierarchical(.disc, .circle, .square)
    }

    var orderedListMarker: some StructuredText.OrderedListMarker {
        .decimal
    }

    var tableStyle: some StructuredText.TableStyle {
        VikuMarkdownTableStyle(palette: palette)
    }

    var tableCellStyle: some StructuredText.TableCellStyle {
        VikuMarkdownTableCellStyle(palette: palette)
    }

    var thematicBreakStyle: some StructuredText.ThematicBreakStyle {
        VikuMarkdownDividerStyle(palette: palette)
    }

    var highlighterTheme: StructuredText.HighlighterTheme {
        .init(
            foregroundColor: DynamicColor(palette.textPrimary),
            backgroundColor: DynamicColor(palette.fieldBackground),
            tokenProperties: [
                .keyword: AnyTextProperty(.foregroundColor(palette.brand), .fontWeight(.semibold)),
                .string: AnyTextProperty(.foregroundColor(palette.brand)),
                .number: AnyTextProperty(.foregroundColor(palette.brand)),
                .boolean: AnyTextProperty(.foregroundColor(palette.brand)),
                .comment: AnyTextProperty(.foregroundColor(palette.textSecondary)),
                .blockComment: AnyTextProperty(.foregroundColor(palette.textSecondary)),
            ],
        )
    }
}

private struct VikuMarkdownHeadingStyle: StructuredText.HeadingStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font(for: configuration.headingLevel))
            .lineSpacing(VikuSpacing.xxs)
            .textual.blockSpacing(.init(top: VikuSpacing.lg, bottom: VikuSpacing.sm))
            .accessibilityAddTraits(.isHeader)
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: VikuFont.title.weight(.bold)
        case 2: VikuFont.title2.weight(.bold)
        case 3: VikuFont.title3.weight(.semibold)
        case 4: VikuFont.headline
        case 5: VikuFont.callout.weight(.semibold)
        default: VikuFont.subheadline.weight(.semibold)
        }
    }
}

private struct VikuMarkdownParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VikuFont.body)
            .lineSpacing(VikuSpacing.xs)
            .textual.blockSpacing(.init(top: VikuSpacing.sm, bottom: VikuSpacing.sm))
    }
}

private struct VikuMarkdownListItemStyle: StructuredText.ListItemStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.sm) {
            configuration.marker
            configuration.block
        }
        .font(VikuFont.body)
    }
}

private struct VikuMarkdownQuoteStyle: StructuredText.BlockQuoteStyle {
    let palette: VikuPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VikuSpacing.md)
            .background(palette.fieldBackground)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(palette.brand)
                    .frame(width: VikuSpacing.xs)
            }
            .clipShape(RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
            .textual.blockSpacing(.init(top: VikuSpacing.md, bottom: VikuSpacing.md))
    }
}

private struct VikuMarkdownCodeStyle: StructuredText.CodeBlockStyle {
    let palette: VikuPalette

    func makeBody(configuration: Configuration) -> some View {
        // Textual's overflow container preserves selection and gestures inside
        // horizontally scrolling code, unlike a separate SwiftUI ScrollView.
        Overflow {
            configuration.label
                .font(VikuFont.callout.monospaced())
                .lineSpacing(VikuSpacing.xs)
                .fixedSize(horizontal: false, vertical: true)
                .padding(VikuSpacing.md)
        }
        .background(palette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        .textual.blockSpacing(.init(top: VikuSpacing.md, bottom: VikuSpacing.md))
    }
}

private struct VikuMarkdownTableStyle: StructuredText.TableStyle {
    let palette: VikuPalette

    func makeBody(configuration: Configuration) -> some View {
        Overflow { state in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: state.containerWidth, alignment: .leading)
                .padding(VikuSpacing.xxs)
                .background(palette.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        }
        .textual.tableCellSpacing(horizontal: VikuSpacing.xxs, vertical: VikuSpacing.xxs)
        .textual.blockSpacing(.init(top: VikuSpacing.md, bottom: VikuSpacing.md))
    }
}

private struct VikuMarkdownTableCellStyle: StructuredText.TableCellStyle {
    let palette: VikuPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VikuFont.callout.weight(configuration.row == 0 ? .semibold : .regular))
            .foregroundStyle(palette.textPrimary)
            .lineSpacing(VikuSpacing.xs)
            .padding(VikuSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(configuration.row == 0 ? palette.fieldBackground : palette.cardBackground)
    }
}

private struct VikuMarkdownDividerStyle: StructuredText.ThematicBreakStyle {
    let palette: VikuPalette

    func makeBody(configuration _: Configuration) -> some View {
        Divider()
            .overlay(palette.textTertiary)
            .textual.blockSpacing(.init(top: VikuSpacing.lg, bottom: VikuSpacing.md))
    }
}
