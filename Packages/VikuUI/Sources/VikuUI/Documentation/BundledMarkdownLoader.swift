import Foundation

/// Reads small, bundled documentation files without requiring connectivity.
/// The caller owns the bundle and supplies a stable resource name, not a path.
public struct BundledMarkdownLoader {
    public enum LoadError: Error, Equatable {
        case missingResource
        case emptyDocument
    }

    private let bundle: Bundle

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    /// Returns the article body without its front matter. See `loadDocument`.
    public func load(
        resource: String,
        preferredLanguages: [String] = Locale.preferredLanguages,
    ) throws -> String {
        try loadDocument(resource: resource, preferredLanguages: preferredLanguages).body
    }

    /// Uses the best supported language, falling back to the English article
    /// if the translated resource is missing. Read failures remain errors.
    public func loadDocument(
        resource: String,
        preferredLanguages: [String] = Locale.preferredLanguages,
    ) throws -> MarkdownFrontMatter {
        guard !resource.isEmpty, !resource.contains("/"), !resource.contains("\\") else {
            throw LoadError.missingResource
        }

        let preferred = Bundle.preferredLocalizations(
            from: ["en", "es"],
            forPreferences: preferredLanguages,
        )
        for language in preferred + ["en"] {
            guard let directory = bundle.url(forResource: language, withExtension: "lproj"),
                  let localizedBundle = Bundle(url: directory),
                  let url = localizedBundle.url(forResource: resource, withExtension: "md")
            else { continue }

            let document = try MarkdownFrontMatter(parsing: String(contentsOf: url, encoding: .utf8))
            guard !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LoadError.emptyDocument
            }
            return document
        }
        throw LoadError.missingResource
    }
}
