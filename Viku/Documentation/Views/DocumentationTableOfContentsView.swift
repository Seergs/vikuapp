import SwiftUI
import VikuDesignSystem
import VikuUI

/// A numbered overview that scrolls to the selected heading in the article.
struct DocumentationTableOfContentsView: View {
    let headings: [MarkdownArticleMetadata.Heading]
    let onSelect: (Int) -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DocumentationCardHeader(title: "In this article")

            DocumentationCardSeparator()

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
                    .padding(.vertical, VikuSpacing.xs)
                    .frame(minHeight: VikuSpacing.xl + VikuSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)

                if index < headings.count - 1 {
                    DocumentationCardSeparator()
                }
            }
        }
        .documentationCard()
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
