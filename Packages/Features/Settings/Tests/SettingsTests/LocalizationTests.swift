import Foundation
@testable import Settings
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
        ("Automatic", "Automático"),
        ("Light", "Claro"),
        ("Dark", "Oscuro"),
        ("API Token", "Token de API"),
        ("Username & Password", "Usuario y contraseña"),
        ("Single Sign-On", "Inicio de sesión único"),
        ("Version", "Versión"),
        ("Build", "Compilación"),
        ("Source Code", "Código fuente"),
        ("Report a Problem", "Reportar un problema"),
        ("Vikunja Project", "Proyecto Vikunja"),
        ("Privacy", "Privacidad"),
        (
            "Viku only talks to the Vikunja instance you connect it to. Your tasks and credentials never pass through any other server.",
            "Viku solo se comunica con la instancia de Vikunja a la que te conectas. Tus tareas y credenciales nunca pasan por ningún otro servidor.",
        ),
        ("License (MIT)", "Licencia (MIT)"),
        (
            "Viku is an independent, unofficial client and isn't affiliated with the Vikunja project. Vikunja itself is licensed under AGPLv3.",
            "Viku es un cliente independiente, no oficial, y no está afiliado al proyecto Vikunja. Vikunja mismo está licenciado bajo AGPLv3.",
        ),
        ("About", "Acerca de"),
        ("Appearance", "Apariencia"),
        ("Connections", "Conexiones"),
        ("Manage Labels", "Administrar etiquetas"),
        ("View, edit, and create labels", "Ver, editar y crear etiquetas"),
        ("Version, links, and privacy", "Versión, enlaces y privacidad"),
        ("Show DEV Badge", "Mostrar insignia DEV"),
        ("Log Network Requests", "Registrar solicitudes de red"),
        ("Preview Onboarding", "Previsualizar onboarding"),
        ("See the first-launch screen again", "Ver otra vez la pantalla de primer inicio"),
        ("Developer", "Desarrollador"),
        ("Settings", "Configuración"),
        ("Connection Name", "Nombre de la conexión"),
        ("e.g. Office Server", "p. ej. Servidor de la oficina"),
        ("Instance URL", "URL de la instancia"),
        ("https://tasks.yourcompany.com", "https://tasks.yourcompany.com"),
        ("Allow Insecure Connection", "Permitir conexión insegura"),
        (
            "Traffic to this instance won't be encrypted. Only use http on a trusted local network.",
            "El tráfico hacia esta instancia no estará cifrado. Usa http solo en una red local de confianza.",
        ),
        (
            "You'll be redirected to your provider's sign-in page to finish.",
            "Serás redirigido a la página de inicio de sesión de tu proveedor para finalizar.",
        ),
        ("Continue with %@", "Continuar con %@"),
        ("Saved", "Guardado"),
        ("Connection successful", "Conexión exitosa"),
        ("Delete Connection", "Eliminar conexión"),
        ("Edit Connection", "Editar conexión"),
        ("New Connection", "Nueva conexión"),
        ("Remove this connection?", "¿Quitar esta conexión?"),
        ("Remove Connection", "Quitar conexión"),
        ("Cancel", "Cancelar"),
        ("Username", "Usuario"),
        ("your-username", "tu-usuario"),
        ("Two-Factor Code", "Código de dos factores"),
        ("123456", "123456"),
        ("Password", "Contraseña"),
        ("••••••••", "••••••••"),
        ("Hide password", "Ocultar contraseña"),
        ("Show password", "Mostrar contraseña"),
        ("vkj_...", "vkj_..."),
        ("Hide token", "Ocultar token"),
        ("Show token", "Mostrar token"),
        ("Generate it on your Vikunja instance: Settings → API Tokens.", "Genéralo en tu instancia de Vikunja: Configuración → Tokens de API."),
        ("Testing connection…", "Probando conexión…"),
        ("Test Connection", "Probar conexión"),
        ("Save Connection", "Guardar conexión"),
        ("Save and Connect", "Guardar y conectar"),
        ("Couldn't load connections", "No se pudieron cargar las conexiones"),
        (
            "Choose the Vikunja instance you want to sync your tasks with.",
            "Elige la instancia de Vikunja con la que quieres sincronizar tus tareas.",
        ),
        ("Add Connection", "Agregar conexión"),
        ("ACTIVE", "ACTIVA"),
        ("Edit %@", "Editar %@"),
        ("New Label", "Nueva etiqueta"),
        ("Delete this label?", "¿Eliminar esta etiqueta?"),
        ("Delete \"%@\"", "Eliminar \"%@\""),
        ("It will be removed from every task it's attached to.", "Se eliminará de todas las tareas en las que esté asignada."),
        ("Couldn't load labels", "No se pudieron cargar las etiquetas"),
        ("No labels yet", "Aún no hay etiquetas"),
        (
            "Create a label to organize tasks across every project.",
            "Crea una etiqueta para organizar tareas en todos los proyectos.",
        ),
        ("Delete", "Eliminar"),
        ("Edit Label", "Editar etiqueta"),
        ("Save", "Guardar"),
        ("Label name", "Nombre de la etiqueta"),
        ("Color", "Color"),
        ("Label created", "Etiqueta creada"),
        ("Label updated", "Etiqueta actualizada"),
        ("Label deleted", "Etiqueta eliminada"),
        ("Connection updated", "Conexión actualizada"),
        ("Connection added", "Conexión agregada"),
        ("You need at least one connection", "Necesitas al menos una conexión"),
        ("Connection removed", "Conexión eliminada"),
        ("Notifications", "Notificaciones"),
        ("Push notifications via Viku Relay", "Notificaciones push vía Viku Relay"),
        ("Push Notifications", "Notificaciones push"),
        ("Requires Viku Relay, a service hosted by the Viku team.", "Requiere Viku Relay, un servicio alojado por el equipo de Viku."),
        ("Vikunja does not send push to iOS directly.", "Vikunja no envía notificaciones push a iOS directamente."),
        ("Notifications are turned off for Viku in iOS Settings.", "Las notificaciones están desactivadas para Viku en los ajustes de iOS."),
        ("Open Settings", "Abrir ajustes"),
        ("User Notifications", "Notificaciones de usuario"),
        ("Reminders & Overdue Tasks", "Recordatorios y tareas vencidas"),
        ("Project Notifications", "Notificaciones de proyecto"),
        ("Task created, updated, assigned, or commented on.", "Tarea creada, actualizada, asignada o comentada."),
        ("Couldn't load projects", "No se pudieron cargar los proyectos"),
        ("Enable push notifications", "Activar notificaciones push"),
        ("Vikunja cannot send notifications to iOS by itself.", "Vikunja no puede enviar notificaciones a iOS por sí solo."),
        (
            "To receive them, Viku connects your instance's webhooks to an intermediary service.",
            "Para recibirlas, Viku conecta los webhooks de tu instancia a un servicio intermediario.",
        ),
        ("Hosted by the Viku team", "Alojado por el equipo de Viku"),
        (
            "Viku Relay receives your instance's webhooks and forwards them to your iPhone through Apple Push Notification service. It is not self-hosted: APNs requires Apple credentials that only the Viku team holds.",
            "Viku Relay recibe los webhooks de tu instancia y los reenvía a tu iPhone a través del servicio de notificaciones push de Apple. No es autoalojado: APNs requiere credenciales de Apple que solo tiene el equipo de Viku.",
        ),
        ("What data goes through the relay", "Qué datos pasan por el relay"),
        (
            "The event type, the task title, and the project name. Your token or password never leaves the device. The webhook signing secret is shared with the relay so it can verify deliveries.",
            "El tipo de evento, el título de la tarea y el nombre del proyecto. Tu token o contraseña nunca salen del dispositivo. El secreto de firma del webhook se comparte con el relay para que pueda verificar las entregas.",
        ),
        ("Your instance needs internet access", "Tu instancia necesita acceso a internet"),
        ("Vikunja has to reach relay.viku.dev over HTTPS.", "Vikunja debe poder alcanzar relay.viku.dev mediante HTTPS."),
        (
            "I understand my events will pass through Viku Relay, a service operated by the Viku team.",
            "Entiendo que mis eventos pasarán por Viku Relay, un servicio operado por el equipo de Viku.",
        ),
        ("Agree & Continue", "Aceptar y continuar"),
        ("Setting up notifications…", "Configurando notificaciones…"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
