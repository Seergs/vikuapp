import Foundation

/// An in-memory index for small, bundled documents. Normalize once when the
/// content changes so typing never reads files or requires a connection.
public struct MarkdownSearchIndex {
    public struct Entry {
        public let id: String
        public let text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    private let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries.map { Entry(id: $0.id, text: Self.normalize($0.text)) }
    }

    /// All query words must occur in the document, regardless of case, accents,
    /// or order. Results retain the catalog's original order.
    public func matchingIDs(query: String) -> [String] {
        let words = Self.normalize(query).split(whereSeparator: \.isWhitespace)
        return entries.filter { entry in
            words.allSatisfy { entry.text.contains($0) }
        }.map(\.id)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
