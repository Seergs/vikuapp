import Foundation
@testable import Tasks
import Testing

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
        ("en", "one", "Blocked · waiting on %lld task"),
        ("en", "other", "Blocked · waiting on %lld tasks"),
        ("es", "one", "Bloqueada · a la espera de %lld tarea"),
        ("es", "other", "Bloqueada · a la espera de %lld tareas"),
    ])
    func `plural variant resolves to the expected translation`(locale: String, category: String, expected: String) {
        #expect(Self.pluralVariant("Blocked · waiting on %lld tasks", locale: locale, category: category) == expected)
    }

    @Test(arguments: [
        ("Couldn't load this task", "No se pudo cargar esta tarea"),
        ("Mark as Not Done", "Marcar como no hecha"),
        ("Mark as Done", "Marcar como hecha"),
        ("Due Date", "Fecha de vencimiento"),
        ("Priority", "Prioridad"),
        ("Labels", "Etiquetas"),
        ("Add Relation", "Agregar relación"),
        ("Duplicate Task", "Duplicar tarea"),
        ("Move to Project", "Mover a proyecto"),
        ("Delete Task", "Eliminar tarea"),
        ("Task Details", "Detalles de la tarea"),
        ("This permanently deletes the task.", "Esto elimina la tarea de forma permanente."),
        ("This permanently deletes the comment.", "Esto elimina el comentario de forma permanente."),
        ("Delete Comment", "Eliminar comentario"),
        ("Cancel", "Cancelar"),
        ("Task title", "Título de la tarea"),
        ("Add description...", "Agregar descripción..."),
        ("Due", "Vence"),
        ("Set due date", "Definir fecha de vencimiento"),
        ("Set priority", "Definir prioridad"),
        ("None", "Ninguna"),
        ("Low", "Baja"),
        ("Medium", "Media"),
        ("High", "Alta"),
        ("Urgent", "Urgente"),
        ("Edit", "Editar"),
        ("Add labels…", "Agregar etiquetas…"),
        ("Subtasks", "Subtareas"),
        ("Relations", "Relaciones"),
        ("Add", "Agregar"),
        ("No relations with other tasks.", "Sin relaciones con otras tareas."),
        ("Show less", "Mostrar menos"),
        ("Show %lld more", "Mostrar %lld más"),
        ("Attachments", "Adjuntos"),
        ("No attachments yet.", "Aún no hay adjuntos."),
        ("Uploading…", "Subiendo…"),
        ("Delete Attachment", "Eliminar adjunto"),
        ("This permanently deletes the attachment.", "Esto elimina el adjunto de forma permanente."),
        ("Comments", "Comentarios"),
        ("No comments yet.", "Aún no hay comentarios."),
        ("Edit Comment", "Editar comentario"),
        ("Write a comment...", "Escribe un comentario..."),
        ("Comment", "Comentario"),
        ("Save", "Guardar"),
        ("New Task", "Nueva tarea"),
        ("Choose Project", "Elegir proyecto"),
        ("Project", "Proyecto"),
        ("Task created", "Tarea creada"),
        ("Relation added", "Relación agregada"),
        ("Task deleted", "Tarea eliminada"),
        ("Attachment added", "Adjunto agregado"),
        ("Attachment deleted", "Adjunto eliminado"),
        ("Couldn't delete attachment", "No se pudo eliminar el adjunto"),
        ("Couldn't read that file", "No se pudo leer ese archivo"),
        ("Couldn't post comment", "No se pudo publicar el comentario"),
        ("Couldn't update comment", "No se pudo actualizar el comentario"),
        ("Couldn't delete comment", "No se pudo eliminar el comentario"),
        ("Task moved to %@", "Tarea movida a %@"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
