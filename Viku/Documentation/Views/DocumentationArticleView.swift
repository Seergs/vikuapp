import SwiftUI
import VikuDesignSystem
import VikuUI

/// A read-only article ready to push onto the caller's navigation stack.
/// Pass resolved display strings; this view does not localize its inputs.
/// A leading Markdown H1 is omitted because navigation already shows the title.
/// Bundled Markdown works offline. Remote images and links require connectivity.
struct DocumentationArticleView: View {
    let title: String
    private let markdown: String
    private let metadata: MarkdownArticleMetadata

    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, markdown: String) {
        self.title = title
        let body = MarkdownArticleBody.removingLeadingHeading(from: markdown)
        self.markdown = body
        self.metadata = MarkdownArticleMetadata(markdown: body)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    if metadata.estimatedReadingMinutes > 0 {
                        HStack(spacing: VikuSpacing.xs) {
                            Image(systemName: "clock")
                                .accessibilityHidden(true)
                            Text(verbatim: String(localized: "\(metadata.estimatedReadingMinutes) min"))
                        }
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: String(
                            localized: "Estimated reading time: \(metadata.estimatedReadingMinutes) min",
                        )))
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
            }
            .background(palette.pageBackground)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.large)
        }
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
