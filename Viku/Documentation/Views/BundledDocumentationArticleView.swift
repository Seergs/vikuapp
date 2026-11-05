import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikuUI

/// Resolves a catalog entry to localized bundled content. The generic article
/// view remains independent of file layout and article selection.
struct BundledDocumentationArticleView: View {
    let articleID: String

    @Environment(AppRouter.self) private var router
    @Environment(\.locale) private var locale

    var body: some View {
        // Bundled guides are small and local, so loading needs no network or
        // intermediate spinner. Missing files produce an explicit error screen.
        if let article = DocumentationArticle(rawValue: articleID),
           let document = load(article),
           let entry = DocumentationEntry(article: article, document: document) {
            DocumentationArticleView(
                title: entry.title,
                summary: entry.summary,
                category: document["category"].flatMap(DocumentationCategory.init(rawValue:))?.title,
                updated: document.date(for: "updated"),
                related: relatedEntries(of: article, in: document),
                markdown: document.body,
                onOpenRelated: { router.push(.documentationArticle($0)) },
            )
        } else {
            ContentUnavailableView {
                Label("Couldn't load the article", systemImage: "doc.text")
                    .font(VikuFont.headline)
            } description: {
                Text("This guide isn't available in this version of the app.")
                    .font(VikuFont.body)
            }
            .navigationTitle("Documentation")
        }
    }

    private func load(_ article: DocumentationArticle) -> MarkdownFrontMatter? {
        try? BundledMarkdownLoader(bundle: .main).loadDocument(
            resource: article.id,
            preferredLanguages: [locale.identifier],
        )
    }

    /// Unknown, unreadable, or self-referencing IDs are skipped, so a typo in
    /// one article's `related` list never hides the article itself.
    private func relatedEntries(
        of article: DocumentationArticle,
        in document: MarkdownFrontMatter,
    ) -> [DocumentationEntry] {
        document.list(for: "related").compactMap { id in
            guard let related = DocumentationArticle(rawValue: id), related != article,
                  let relatedDocument = load(related)
            else { return nil }
            return DocumentationEntry(article: related, document: relatedDocument)
        }
    }
}
