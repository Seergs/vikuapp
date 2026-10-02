import Foundation
@testable import Search
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
        ("Search tasks", "Buscar tareas"),
        ("Search", "Buscar"),
        ("This permanently deletes the task.", "Esto elimina la tarea de forma permanente."),
        ("Delete Task", "Eliminar tarea"),
        ("Cancel", "Cancelar"),
        ("Search Tasks", "Buscar tareas"),
        ("Type a query to search all your tasks", "Escribe una búsqueda para buscar en todas tus tareas"),
        ("No Results", "Sin resultados"),
        ("No tasks match your search", "Ninguna tarea coincide con tu búsqueda"),
        ("Search Error", "Error de búsqueda"),
        ("RESULTS", "RESULTADOS"),
        ("Mark as Not Done", "Marcar como no hecha"),
        ("Mark as Done", "Marcar como hecha"),
        ("Delete", "Eliminar"),
        ("Search failed", "Error al buscar"),
        ("Could not load project details", "No se pudieron cargar los detalles del proyecto"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
