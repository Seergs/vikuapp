import Foundation
import Testing
@testable import VikunjaCore

/// Verifies the module's `Localizable.xcstrings` has a translated Spanish
/// entry for every key `VikunjaError+DisplayMessage.swift` references.
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
    /// Resolves `VikunjaCore`'s own resource bundle rather than this
    /// target's `Bundle.module` — this file compiles into `VikunjaCoreTests`,
    /// so once that target declares any resources of its own (see
    /// `Fixtures/`), SPM generates a `Bundle.module` accessor for
    /// *this* module, which shadows the one `@testable import VikunjaCore`
    /// would otherwise fall back to. The two targets' bundles sit side by
    /// side wherever SPM places `Bundle.module`'s own bundle, so that's used
    /// as the anchor to find VikunjaCore's sibling bundle by its SPM-assigned
    /// name (`<package>_<target>.bundle`).
    private static let vikunjaCoreBundle: Bundle = {
        let bundleName = "VikunjaCore_VikunjaCore.bundle"
        let candidates = [
            Bundle.main.bundleURL,
            Bundle.module.bundleURL.deletingLastPathComponent(),
        ]
        for candidate in candidates {
            if let bundle = Bundle(url: candidate.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        fatalError("could not locate \(bundleName)")
    }()

    private static func loadCatalog() -> [String: Any] {
        guard let url = vikunjaCoreBundle.url(forResource: "Localizable", withExtension: "xcstrings"),
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
        ("That doesn't look like a valid instance address.", "Eso no parece una dirección de instancia válida."),
        ("That address uses an insecure http connection.", "Esa dirección usa una conexión http insegura."),
        (
            "Couldn't reach that server. Check the address and your connection.",
            "No se pudo conectar con ese servidor. Revisa la dirección y tu conexión.",
        ),
        ("That address didn't respond like a Vikunja instance.", "Esa dirección no respondió como una instancia de Vikunja."),
        ("That server rejected the request.", "Ese servidor rechazó la solicitud."),
        ("The server responded with an error (%lld).", "El servidor respondió con un error (%lld)."),
        ("This app needs Vikunja %@ or newer.", "Esta app necesita Vikunja %@ o una versión más reciente."),
        ("This account needs a two-factor code.", "Esta cuenta necesita un código de dos factores."),
        ("Your session expired. Sign in again to continue.", "Tu sesión expiró. Inicia sesión de nuevo para continuar."),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
