import Foundation
import Testing
@testable import WhatsNew

/// Verifies the module's `Localizable.xcstrings` has a translated Spanish
/// entry for every key this module's code references. See `VikunjaCore`'s
/// own `LocalizationTests` for why this reads the catalog's JSON directly
/// rather than resolving `String(localized:bundle:)` at runtime.
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

    private static func es(_ key: String) -> String? {
        guard let entry = loadCatalog()[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let spanish = localizations["es"] as? [String: Any],
              let unit = spanish["stringUnit"] as? [String: Any],
              unit["state"] as? String == "translated"
        else { return nil }
        return unit["value"] as? String
    }

    @Test(arguments: [
        ("VERSION", "VERSIÓN"),
        ("Fixes & improvements", "Mejoras y correcciones"),
        ("See previous versions", "Ver versiones anteriores"),
        ("Version", "Versión"),
        ("Version history", "Historial de versiones"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
