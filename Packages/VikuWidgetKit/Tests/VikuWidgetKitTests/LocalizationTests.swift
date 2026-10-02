import Foundation
import Testing
@testable import VikuWidgetKit

/// Verifies the module's `Localizable.xcstrings` has translated Spanish
/// entries (plural and plain) for every key this module's code references.
/// See `Features/Home`'s `LocalizationTests` for why this only checks catalog
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
        ("en", "one", "%lld task"),
        ("en", "other", "%lld tasks"),
        ("es", "one", "%lld tarea"),
        ("es", "other", "%lld tareas"),
    ])
    func `plural variant resolves to the expected translation`(locale: String, category: String, expected: String) {
        #expect(Self.pluralVariant("%lld tasks", locale: locale, category: category) == expected)
    }

    @Test(arguments: [
        ("Not connected", "No conectado"),
        ("Open Vikunja to add your instance.", "Abre Vikunja para agregar tu instancia."),
        ("Sign in again", "Inicia sesión de nuevo"),
        (
            "Your token was rejected. Re-add the connection in Settings.",
            "Tu token fue rechazado. Vuelve a agregar la conexión en Configuración.",
        ),
        ("Couldn't refresh", "No se pudo actualizar"),
        ("No connection and nothing saved yet.", "Sin conexión y aún no hay nada guardado."),
        ("Nothing due. Enjoy it.", "Nada pendiente. Disfrútalo."),
        ("Today", "Hoy"),
        ("Showing saved data", "Mostrando datos guardados"),
        ("Add task", "Agregar tarea"),
        ("Overdue", "Vencida"),
        ("Open Viku to add your instance.", "Abre Viku para agregar tu instancia."),
        ("Nothing due today.", "Nada pendiente hoy."),
        ("Add Task", "Agregar tarea"),
        (
            "Opens Viku's quick-add sheet to jot down a new task.",
            "Abre la hoja de agregado rápido de Viku para anotar una tarea nueva.",
        ),
        ("Open Viku's quick-add sheet.", "Abre la hoja de agregado rápido de Viku."),
        ("Toggle Task Completion", "Alternar finalización de tarea"),
        ("Marks a Vikunja task done or not done.", "Marca una tarea de Vikunja como hecha o no hecha."),
        ("Task ID", "ID de tarea"),
        ("Tasks that are overdue, due today, or coming up.", "Tareas vencidas, que vencen hoy, o próximas."),
        ("Calendar", "Calendario"),
        ("This month's tasks at a glance, with today's list.", "Las tareas de este mes de un vistazo, con la lista de hoy."),
        ("The Viku glyph as a one-tap shortcut to add a task.", "El glifo de Viku como acceso directo de un toque para agregar una tarea."),
        ("%lld overdue · %lld today", "%lld vencidas · %lld hoy"),
        ("%lld today · %lld upcoming", "%lld hoy · %lld próximas"),
        ("+%lld more", "+%lld más"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
