import SwiftUI
import VikuDesignSystem
import VikuUI

/// A numbered overview that scrolls to the selected heading in the article.
struct DocumentationTableOfContentsView: View {
    let headings: [MarkdownArticleMetadata.Heading]
    let onSelect: (Int) -> Void

    @Environment(\.vikuPalette) private var palette
    @Environment(\.displayScale) private var displayScale

    private var borderColor: Color {
        palette.textTertiary.opacity(0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("In this article")
                .textCase(.uppercase)
                .font(VikuFont.caption.weight(.bold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VikuSpacing.md)

            separator

            ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                Button {
                    onSelect(heading.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.md + VikuSpacing.xs) {
                        Text(verbatim: (index + 1).formatted(
                            .number.grouping(.never).precision(.integerLength(2...)),
                        ))
                        .font(VikuFont.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.brand)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: VikuSpacing.lg, alignment: .leading)

                        Text(verbatim: heading.title)
                            .font(VikuFont.subheadline)
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                    .padding(.vertical, VikuSpacing.sm)
                    .frame(minHeight: VikuSpacing.xxl - VikuSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)

                if index < headings.count - 1 {
                    separator
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
                .strokeBorder(borderColor)
                .allowsHitTesting(false)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(borderColor)
            .frame(height: 1 / displayScale)
    }
}

#Preview {
    DocumentationTableOfContentsView(
        headings: MarkdownArticleMetadata(markdown: """
        ## Before you go offline
        ## What you can do
        ## What needs a connection
        ## What happens when you reconnect
        """).tableOfContents,
        onSelect: { _ in },
    )
    .padding(VikuSpacing.lg)
    .background(VikuPalette.standard.pageBackground)
}
