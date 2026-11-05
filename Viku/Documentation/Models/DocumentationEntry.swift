import VikuUI

/// An article's localized index text, read from its front matter.
struct DocumentationEntry: Identifiable {
    let article: DocumentationArticle
    let title: String
    let summary: String

    var id: String {
        article.id
    }

    /// Requires a title; the summary is optional.
    init?(article: DocumentationArticle, document: MarkdownFrontMatter) {
        guard let title = document["title"], !title.isEmpty else { return nil }
        self.article = article
        self.title = title
        self.summary = document["summary"] ?? ""
    }
}
