import Foundation
import Observation
import VikuUI

@MainActor
@Observable
final class DocumentationIndexViewModel {
    var query = ""
    private var allEntries: [DocumentationEntry] = []
    private var searchIndex = MarkdownSearchIndex(entries: [])
    @ObservationIgnored private var loadedLanguages: [String]?
    @ObservationIgnored private let loader: BundledMarkdownLoader

    /// Bundled guides are small and local, so loading synchronously on creation
    /// means the first frame already shows the index.
    init(
        loader: BundledMarkdownLoader = BundledMarkdownLoader(bundle: .main),
        preferredLanguages: [String] = Locale.preferredLanguages,
    ) {
        self.loader = loader
        load(preferredLanguages: preferredLanguages)
    }

    var entries: [DocumentationEntry] {
        let matches = Set(searchIndex.matchingIDs(query: query))
        return allEntries.filter { matches.contains($0.id) }
    }

    /// Reloads titles, summaries, and search text for the given languages.
    /// An article without a readable file or a title is left out of the index.
    func load(preferredLanguages: [String]) {
        guard loadedLanguages != preferredLanguages else { return }
        loadedLanguages = preferredLanguages

        var entries: [DocumentationEntry] = []
        var searchEntries: [MarkdownSearchIndex.Entry] = []
        for article in DocumentationArticle.allCases {
            let document = try? loader.loadDocument(
                resource: article.id,
                preferredLanguages: preferredLanguages,
            )
            guard let document, let entry = DocumentationEntry(article: article, document: document) else {
                continue
            }

            entries.append(entry)
            searchEntries.append(.init(
                id: article.id,
                text: [entry.title, entry.summary, document.body].joined(separator: "\n"),
            ))
        }
        allEntries = entries
        searchIndex = MarkdownSearchIndex(entries: searchEntries)
    }
}
