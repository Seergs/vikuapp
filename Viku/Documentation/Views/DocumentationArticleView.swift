import SwiftUI
import VikuDesignSystem
import VikuUI

/// A read-only article ready to push onto the caller's navigation stack.
/// Pass resolved display strings; this view does not localize its inputs.
/// Optional context (summary, category, update date, related guides) is shown
/// only when provided.
/// A leading Markdown H1 is omitted because navigation already shows the title.
/// Bundled Markdown works offline. Remote images and links require connectivity.
struct DocumentationArticleView: View {
    let title: String
    private let summary: String
    private let category: String?
    private let updated: Date?
    private let related: [DocumentationEntry]
    private let onOpenRelated: (String) -> Void
    private let markdown: String
    private let metadata: MarkdownArticleMetadata

    @Environment(\.vikuPalette) private var palette
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        summary: String = "",
        category: String? = nil,
        updated: Date? = nil,
        related: [DocumentationEntry] = [],
        markdown: String,
        onOpenRelated: @escaping (String) -> Void = { _ in },
    ) {
        self.title = title
        self.summary = summary
        self.category = category
        self.updated = updated
        self.related = related
        self.onOpenRelated = onOpenRelated
        let body = MarkdownArticleBody.removingLeadingHeading(from: markdown)
        self.markdown = body
        self.metadata = MarkdownArticleMetadata(markdown: body)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                        header

                        if !summary.isEmpty {
                            Text(verbatim: summary)
                                .font(VikuFont.body)
                                .foregroundStyle(palette.textSecondary)
                                .padding(.vertical, VikuSpacing.sm)
                        }

                        if let updated {
                            Text(verbatim: String(localized: "Updated \(formatted(updated))"))
                                .textCase(.uppercase)
                                .font(VikuFont.caption.weight(.bold))
                                .foregroundStyle(palette.textTertiary)
                                .padding(.bottom, VikuSpacing.sm)
                        }

                        if !metadata.tableOfContents.isEmpty {
                            DocumentationTableOfContentsView(
                                headings: metadata.tableOfContents,
                                onSelect: { id in scrollToHeading(id, using: proxy) },
                            )
                            .padding(.vertical, VikuSpacing.sm)
                        }

                        MarkdownContentView(markdown: markdown)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VikuSpacing.lg)
                    .padding(.vertical, VikuSpacing.md)

                    if !related.isEmpty {
                        DocumentationRelatedArticlesView(entries: related, onSelect: onOpenRelated)
                    }
                }
            }
            .background(palette.pageBackground)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private var header: some View {
        if metadata.estimatedReadingMinutes > 0 || category != nil {
            HStack(spacing: VikuSpacing.sm) {
                if let category {
                    Text(verbatim: category)
                        .textCase(.uppercase)
                        .fontWeight(.bold)
                        .foregroundStyle(palette.brand)
                }

                if category != nil, metadata.estimatedReadingMinutes > 0 {
                    Text(verbatim: "\u{00B7}")
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityHidden(true)
                }

                if metadata.estimatedReadingMinutes > 0 {
                    HStack(spacing: VikuSpacing.xs) {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                        Text(verbatim: String(localized: "\(metadata.estimatedReadingMinutes) min"))
                    }
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: String(
                        localized: "Estimated reading time: \(metadata.estimatedReadingMinutes) min",
                    )))
                }
            }
            .font(VikuFont.footnote)
        }
    }

    /// The written day is the same everywhere, so format it in UTC.
    private func formatted(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(timeZone: .gmt).day().month(.abbreviated).year().locale(locale),
        )
    }

    private func scrollToHeading(_ id: Int, using proxy: ScrollViewProxy) {
        guard let heading = metadata.tableOfContents.first(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(heading.anchor, anchor: .top)
        }
    }
}

#if DEBUG
private let articlePreviewMarkdown = """
# Getting started

Keep your work organized with **projects**, *labels*, and due dates.

# Heading level 1

## Create your first project

1. Open the Projects tab.
2. Create a project with a descriptive name.
3. Add a task and choose a due date.

### Make it yours

- Group related work in subprojects.
- Add **labels** to find tasks across projects.
  - Use a label for each area of your work.
- Use `priority` to highlight what matters next.

#### Heading level 4

Normal text with ~~strikethrough~~ and **strong emphasis**.

##### Heading level 5

Body text keeps the same Dynamic Type size across sections.

###### Heading level 6

The smallest heading still uses a named Viku font token.

> Tip: keep task titles short and put supporting details in the description.

## Example

```json
{
  "title": "Plan the week",
  "priority": 2
}
```

| Feature | Purpose |
| --- | --- |
| Projects | Organize related work |
| Labels | Find tasks across projects |

---

Learn more in the [Vikunja documentation](https://vikunja.io/help/).
"""

private let relatedPreviewEntry = DocumentationEntry(
    article: .quickAddShortcuts,
    document: MarkdownFrontMatter(parsing: """
    ---
    title: Quick-Add Shortcuts
    summary: Set projects and labels as you type.
    ---
    """),
)

#Preview("Article — Full metadata") {
    NavigationStack {
        DocumentationArticleView(
            title: "Getting started",
            summary: "Work offline and sync your changes later.",
            category: "Basics",
            updated: Date(timeIntervalSince1970: 1_792_713_600),
            related: [relatedPreviewEntry].compactMap(\.self),
            markdown: articlePreviewMarkdown,
        )
    }
}

#Preview("Article — Light") {
    NavigationStack {
        DocumentationArticleView(title: "Getting started", markdown: articlePreviewMarkdown)
    }
    .preferredColorScheme(.light)
}

#Preview("Article — Dark") {
    NavigationStack {
        DocumentationArticleView(title: "Getting started", markdown: articlePreviewMarkdown)
    }
    .preferredColorScheme(.dark)
}

#Preview("Article — Accessibility") {
    NavigationStack {
        DocumentationArticleView(title: "Getting started", markdown: articlePreviewMarkdown)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Article — Nord") {
    NavigationStack {
        DocumentationArticleView(title: "Getting started", markdown: articlePreviewMarkdown)
    }
    .environment(\.vikuPalette, .nord)
    .preferredColorScheme(.dark)
}

#Preview("Article — Empty") {
    NavigationStack {
        DocumentationArticleView(title: "Getting started", markdown: "")
    }
}
#endif
