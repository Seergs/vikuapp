import Foundation
@testable import Home
import Testing

/// Verifies the module's `Localizable.xcstrings` has translated Spanish
/// plural variants for every key this module's code references.
///
/// This reads the catalog's JSON directly rather than resolving
/// `String(localized:bundle:)` at runtime: only Xcode's build system
/// compiles a `.xcstrings` file into the `.strings`/`.stringsdict` Foundation
/// actually looks up at runtime. Plain `swift build`/`swift test` from the
/// command line just copies the raw `.xcstrings` JSON into the resource
/// bundle uncompiled, so neither the translation nor the plural-rule
/// selection applies under `swift test` regardless of whether the catalog is
/// correct. Command-line tests can therefore only check the catalog's
/// *content*; verifying the right singular/plural form actually renders in
/// Spanish requires building/running through Xcode.
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
        ("en", "one", "%lld task pending"),
        ("en", "other", "%lld tasks pending"),
        ("es", "one", "%lld tarea pendiente"),
        ("es", "other", "%lld tareas pendientes"),
    ])
    func `plural variant resolves to the expected translation`(locale: String, category: String, expected: String) {
        #expect(Self.pluralVariant("%lld tasks pending", locale: locale, category: category) == expected)
    }
}
