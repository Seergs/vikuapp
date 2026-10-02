@testable import CalendarFeature
import Foundation
import Testing

/// Verifies the module's `Localizable.xcstrings` has a translated Spanish
/// entry for every key this module's code references. See `Features/Home`'s
/// `LocalizationTests` for why this only checks catalog *content*, not
/// runtime rendering (`swift test` doesn't compile `.xcstrings`).
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
        ("Calendar", "Calendario"),
        ("Couldn't load your tasks", "No se pudieron cargar tus tareas"),
        ("No tasks this day.", "Sin tareas este día."),
        ("Overdue", "Vencida"),
        ("Today", "Hoy"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
