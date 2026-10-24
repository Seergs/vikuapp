import Foundation

/// Loads `WhatsNewContent` from a `whats-new_<languageCode>.json` file
/// bundled with the app, falling back to English when `locale`'s language
/// isn't one of the shipped translations.
///
/// Never throws: a missing file, an unreadable one, or one that fails to
/// decode are all treated as `nil` — "nothing to show" — rather than
/// crashing or blocking app launch. `bundle` defaults to `.main` for
/// production use and is overridable so tests can point at a fixture
/// bundle instead.
public struct BundledWhatsNewContentProvider: WhatsNewContentProviding {
    /// The language codes a `whats-new_<code>.json` file is shipped for.
    private static let supportedLanguageCodes: Set<String> = ["en", "es"]
    private static let fallbackLanguageCode = "en"

    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func content(for locale: Locale) -> WhatsNewContent? {
        let code = resolvedLanguageCode(for: locale)
        guard let url = bundle.url(forResource: "whats-new_\(code)", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(WhatsNewContent.self, from: data)
    }

    private func resolvedLanguageCode(for locale: Locale) -> String {
        guard let code = locale.language.languageCode?.identifier,
              Self.supportedLanguageCodes.contains(code)
        else {
            return Self.fallbackLanguageCode
        }
        return code
    }
}
