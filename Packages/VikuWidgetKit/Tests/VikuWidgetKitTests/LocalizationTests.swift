import Foundation
import Testing
@testable import VikuWidgetKit

/// Verifies the module's `Localizable.xcstrings` has translated Spanish
/// plural variants for every key this module's code references. See
/// `Features/Home`'s `LocalizationTests` for why this only checks catalog
/// *content*, not runtime rendering (`swift test` doesn't compile
/// `.xcstrings`).
struct LocalizationTests {
    private static func loadCatalog() -> [String: Any] {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any]
        else {
            Issue.record("could not load or parse Localizable.xcstrings")
            return [:]
        }
        return strings
    }

    private static func pluralVariant(_ key: String, locale: String, category: String) -> String? {
        guard let entry = loadCatalog()[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let localization = localizations[locale] as? [String: Any],
              let variations = localization["variations"] as? [String: Any],
              let plural = variations["plural"] as? [String: Any],
              let variant = plural[category] as? [String: Any],
              let unit = variant["stringUnit"] as? [String: Any],
              unit["state"] as? String == "translated"
        else { return nil }
        return unit["value"] as? String
    }

    @Test(arguments: [
        ("en", "one", "%lld task"),
        ("en", "other", "%lld tasks"),
        ("es", "one", "%lld tarea"),
        ("es", "other", "%lld tareas"),
    ])
    func `plural variant resolves to the expected translation`(locale: String, category: String, expected: String) {
        #expect(Self.pluralVariant("%lld tasks", locale: locale, category: category) == expected)
    }
}
