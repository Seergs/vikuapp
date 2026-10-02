import Foundation
@testable import Onboarding
import Testing

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
        ("Connect your instance", "Conecta tu instancia"),
        (
            "This app connects to your own Vikunja server. Enter your instance's details to get started.",
            "Esta app se conecta a tu propio servidor de Vikunja. Ingresa los datos de tu instancia para comenzar.",
        ),
        ("Connection name", "Nombre de la conexión"),
        ("e.g. Office server", "p. ej. Servidor de la oficina"),
        ("Instance URL", "URL de la instancia"),
        ("https://tasks.example.com", "https://tasks.example.com"),
        ("Allow insecure connection", "Permitir conexión insegura"),
        (
            "Traffic to this instance won't be encrypted. Only use http on a trusted local network.",
            "El tráfico hacia esta instancia no estará cifrado. Usa http solo en una red local de confianza.",
        ),
        ("You'll be redirected to your provider's sign-in page to finish.", "Serás redirigido a la página de inicio de sesión de tu proveedor para finalizar."),
        ("Continue with %@", "Continuar con %@"),
        ("API token", "Token de API"),
        ("vkj_...", "vkj_..."),
        ("Generate one on your Vikunja instance: Settings → API Tokens.", "Genera uno en tu instancia de Vikunja: Configuración → Tokens de API."),
        ("Username", "Usuario"),
        ("your-username", "tu-usuario"),
        ("Password", "Contraseña"),
        ("••••••••", "••••••••"),
        ("Two-factor code", "Código de dos factores"),
        ("123456", "123456"),
        ("Enter the current code from your authenticator app.", "Ingresa el código actual de tu app de autenticación."),
        ("Testing connection…", "Probando conexión…"),
        ("Test Connection", "Probar conexión"),
        ("Save & Continue", "Guardar y continuar"),
        ("Connection successful.", "Conexión exitosa."),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
