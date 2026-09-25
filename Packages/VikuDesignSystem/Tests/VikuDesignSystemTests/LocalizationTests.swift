import Foundation
import Testing
@testable import VikuDesignSystem

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
/// building/running through Xcode (see VIKU-88's simulator check).
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
        ("Access method", "Método de acceso"),
        ("API Token", "Token de API"),
        ("Username & Password", "Usuario y contraseña"),
        ("SSO / OpenID", "SSO / OpenID"),
        ("Current", "Actual"),
        ("Not available on this server, or not confirmed yet.", "No disponible en este servidor, o aún no confirmado."),
        ("Priority", "Prioridad"),
        ("Choose project", "Elegir proyecto"),
        ("Low", "Baja"),
        ("Medium", "Media"),
        ("High", "Alta"),
        ("Urgent", "Urgente"),
        ("Overdue", "Vencida"),
        ("Search projects...", "Buscar proyectos..."),
        ("Cancel", "Cancelar"),
        ("None", "Ninguno"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
