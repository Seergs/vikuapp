import SwiftUI
import VikuDesignSystem
import VikuUI

/// Resolves a catalog entry to localized bundled content. The generic article
/// view remains independent of file layout and article selection.
struct BundledDocumentationArticleView: View {
    let articleID: String

    @Environment(\.locale) private var locale

    var body: some View {
        // Bundled guides are small and local, so loading needs no network or
        // intermediate spinner. Missing files produce an explicit error screen.
        if let article = DocumentationArticle(rawValue: articleID),
           let markdown = try? BundledMarkdownLoader(bundle: .main).load(
               resource: article.id,
               preferredLanguages: [locale.identifier],
           ) {
            DocumentationArticleView(
                title: article.title,
                markdown: markdown,
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
}
