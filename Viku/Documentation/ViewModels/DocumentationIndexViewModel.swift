import Foundation
import Observation
import VikuUI

@MainActor
@Observable
final class DocumentationIndexViewModel {
    var query = ""
    private var searchIndex: MarkdownSearchIndex?
    @ObservationIgnored private let loader: BundledMarkdownLoader

    init(loader: BundledMarkdownLoader = BundledMarkdownLoader(bundle: .main)) {
        self.loader = loader
    }

    var articles: [DocumentationArticle] {
        guard let searchIndex else { return DocumentationArticle.allCases }
        let matches = Set(searchIndex.matchingIDs(query: query))
        return DocumentationArticle.allCases.filter { matches.contains($0.id) }
    }

    func loadSearchIndex(preferredLanguages: [String]) {
        searchIndex = MarkdownSearchIndex(entries: DocumentationArticle.allCases.map { article in
            // Keep metadata searchable even if an article file is unavailable;
            // opening it still presents the existing localized error screen.
            let markdown = try? loader.load(resource: article.id, preferredLanguages: preferredLanguages)
            return MarkdownSearchIndex.Entry(
                id: article.id,
                text: [article.title, article.summary, markdown ?? ""].joined(separator: "\n"),
            )
        })
    }
}
