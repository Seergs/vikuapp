import SwiftUI
import VikuDesignSystem

/// A read-only article ready to push onto the caller's navigation stack.
/// Pass resolved display strings; this view does not localize its inputs.
/// Bundled Markdown works offline. Remote images and links require connectivity.
struct DocumentationArticleView: View {
    let title: String
    let markdown: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        ScrollView {
            MarkdownContentView(markdown: markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VikuSpacing.lg)
                .padding(.vertical, VikuSpacing.md)
        }
        .background(palette.pageBackground)
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.large)
    }
}

#if DEBUG
private let articlePreviewMarkdown = """
Keep your work organized with **projects**, *labels*, and due dates.

## Create your first project

1. Open the Projects tab.
2. Create a project with a descriptive name.
3. Add a task and choose a due date.

### Make it yours

- Group related work in subprojects.
- Add **labels** to find tasks across projects.
  - Use a label for each area of your work.
- Use `priority` to highlight what matters next.

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

#Preview("Article — Empty") {
    NavigationStack {
        DocumentationArticleView(title: "Getting started", markdown: "")
    }
}
#endif
