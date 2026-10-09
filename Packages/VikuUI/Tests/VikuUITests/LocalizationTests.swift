import Foundation
import Testing
@testable import VikuUI

/// Verifies the module's `Localizable.xcstrings` has a translated Spanish
/// entry for every key this module's code references.
///
/// This reads the catalog's JSON directly rather than resolving
/// `String(localized:bundle:)` at runtime: only Xcode's build system
/// compiles a `.xcstrings` file into the `.strings` Foundation actually
/// looks up at runtime (its "Compile String Catalogs" build phase). Plain
/// `swift build`/`swift test` from the command line just copies the raw
/// `.xcstrings` JSON into the resource bundle uncompiled, so any
/// `String(localized:)`/`Text(_:bundle:)` call silently falls back to the
/// source-language string under `swift test` regardless of whether the
/// catalog is correct. Command-line tests can therefore only check the
/// catalog's *content*; verifying it actually renders in Spanish requires
/// building/running through Xcode.
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
        ("Try Again", "Reintentar"),
        ("Relation Type", "Tipo de relación"),
        ("Cancel", "Cancelar"),
        ("Search tasks...", "Buscar tareas..."),
        ("No results", "Sin resultados"),
        ("No other tasks in this project", "No hay otras tareas en este proyecto"),
        ("Subtasks", "Subtareas"),
        ("Parent Task", "Tarea principal"),
        ("Related Tasks", "Tareas relacionadas"),
        ("Duplicate Of", "Duplicado de"),
        ("Duplicates", "Duplicados"),
        ("Blocks", "Bloquea"),
        ("Depends On", "Depende de"),
        ("Precedes", "Precede a"),
        ("Follows", "Sigue a"),
        ("Copied From", "Copiado de"),
        ("Copied To", "Copiado a"),
        ("Labels", "Etiquetas"),
        ("Done", "Listo"),
        ("Create New Label", "Crear nueva etiqueta"),
        ("Create and Add", "Crear y agregar"),
        ("Duplicate Task", "Duplicar tarea"),
        ("Duplicate", "Duplicar"),
        ("Remove Due Date", "Quitar fecha de vencimiento"),
        ("Due Date", "Fecha de vencimiento"),
        ("Save", "Guardar"),
        ("Reminder", "Recordatorio"),
        ("Reminder type", "Tipo de recordatorio"),
        ("Specific Date", "Fecha específica"),
        ("Relative", "Relativo"),
        ("Remove Reminder", "Quitar recordatorio"),
        ("due date", "fecha de vencimiento"),
        ("start date", "fecha de inicio"),
        ("end date", "fecha de finalización"),
        ("At %@", "En %@"),
        ("Minutes", "Minutos"),
        ("Hours", "Horas"),
        ("Days", "Días"),
        ("Weeks", "Semanas"),
        ("Before", "Antes"),
        ("After", "Después"),
        ("Relative to", "Respecto a"),
        ("Unit", "Unidad"),
        ("Direction", "Dirección"),
        ("Quantity", "Cantidad"),
        ("That time has already passed: %@", "Esa hora ya pasó: %@"),
        ("It will move if you change the due date.", "Se moverá si cambias la fecha límite."),
        ("Will ring %@", "Sonará %@"),
        ("today at %@", "hoy a las %@"),
        ("tomorrow at %@", "mañana a las %@"),
        ("%@ at %@", "%@ a las %@"),
        ("%@, %@", "%@, %@"),
        ("On time", "A la hora"),
        ("15 min before", "15 min antes"),
        ("30 min before", "30 min antes"),
        ("1 hour before", "1 hora antes"),
        ("1 day before", "1 día antes"),
        ("1 week before", "1 semana antes"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }

    @Test(arguments: [
        ("en", "one", "%lld hours before %@", "%lld hour before %@"),
        ("en", "other", "%lld hours before %@", "%lld hours before %@"),
        ("es", "one", "%lld hours before %@", "%lld hora antes de %@"),
        ("es", "other", "%lld hours before %@", "%lld horas antes de %@"),
        ("en", "one", "%lld hours after %@", "%lld hour after %@"),
        ("en", "other", "%lld hours after %@", "%lld hours after %@"),
        ("es", "one", "%lld hours after %@", "%lld hora después de %@"),
        ("es", "other", "%lld hours after %@", "%lld horas después de %@"),
        ("en", "one", "%lld days before %@", "%lld day before %@"),
        ("en", "other", "%lld days before %@", "%lld days before %@"),
        ("es", "one", "%lld days before %@", "%lld día antes de %@"),
        ("es", "other", "%lld days before %@", "%lld días antes de %@"),
        ("en", "one", "%lld days after %@", "%lld day after %@"),
        ("en", "other", "%lld days after %@", "%lld days after %@"),
        ("es", "one", "%lld days after %@", "%lld día después de %@"),
        ("es", "other", "%lld days after %@", "%lld días después de %@"),
        ("en", "one", "%lld weeks before %@", "%lld week before %@"),
        ("en", "other", "%lld weeks before %@", "%lld weeks before %@"),
        ("es", "one", "%lld weeks before %@", "%lld semana antes de %@"),
        ("es", "other", "%lld weeks before %@", "%lld semanas antes de %@"),
        ("en", "one", "%lld weeks after %@", "%lld week after %@"),
        ("en", "other", "%lld weeks after %@", "%lld weeks after %@"),
        ("es", "one", "%lld weeks after %@", "%lld semana después de %@"),
        ("es", "other", "%lld weeks after %@", "%lld semanas después de %@"),
        ("en", "one", "%lld minutes before %@", "%lld minute before %@"),
        ("en", "other", "%lld minutes before %@", "%lld minutes before %@"),
        ("es", "one", "%lld minutes before %@", "%lld minuto antes de %@"),
        ("es", "other", "%lld minutes before %@", "%lld minutos antes de %@"),
        ("en", "one", "%lld minutes after %@", "%lld minute after %@"),
        ("en", "other", "%lld minutes after %@", "%lld minutes after %@"),
        ("es", "one", "%lld minutes after %@", "%lld minuto después de %@"),
        ("es", "other", "%lld minutes after %@", "%lld minutos después de %@"),
    ])
    func `plural variant resolves to the expected translation`(
        locale: String, category: String, key: String, expected: String,
    ) {
        #expect(Self.pluralVariant(key, locale: locale, category: category) == expected)
    }
}
