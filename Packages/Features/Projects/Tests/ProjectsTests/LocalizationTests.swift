import Foundation
@testable import Projects
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
        ("en", "one", "%lld project"),
        ("en", "other", "%lld projects"),
        ("es", "one", "%lld proyecto"),
        ("es", "other", "%lld proyectos"),
    ])
    func `plural variant resolves to the expected translation`(locale: String, category: String, expected: String) {
        #expect(Self.pluralVariant("%lld projects", locale: locale, category: category) == expected)
    }

    @Test(arguments: [
        ("This permanently deletes the task.", "Esto elimina la tarea de forma permanente."),
        ("Delete Task", "Eliminar tarea"),
        ("Cancel", "Cancelar"),
        ("Move to Project", "Mover a proyecto"),
        ("Couldn't load this project", "No se pudo cargar este proyecto"),
        ("Subprojects", "Subproyectos"),
        ("No tasks yet", "Aún no hay tareas"),
        ("Nothing here", "No hay nada aquí"),
        ("Tasks in this project will show up here.", "Las tareas de este proyecto aparecerán aquí."),
        ("No tasks match this filter.", "Ninguna tarea coincide con este filtro."),
        ("Mark as Done", "Marcar como hecha"),
        ("Mark as Not Done", "Marcar como no hecha"),
        ("Due Date", "Fecha de vencimiento"),
        ("Priority", "Prioridad"),
        ("Labels", "Etiquetas"),
        ("Add Relation", "Agregar relación"),
        ("Duplicate Task", "Duplicar tarea"),
        ("Edit Project", "Editar proyecto"),
        ("All", "Todas"),
        ("Pending", "Pendientes"),
        ("Overdue", "Vencidas"),
        ("Completed", "Completadas"),
        ("Sort", "Ordenar"),
        ("Sort By", "Ordenar por"),
        ("Order", "Orden"),
        ("Alphabetical", "Alfabético"),
        ("Ascending", "Ascendente"),
        ("Descending", "Descendente"),
        ("Project", "Proyecto"),
        ("List", "Lista"),
        ("Kanban", "Kanban"),
        ("None", "Ninguno"),
        ("Low", "Baja"),
        ("Medium", "Media"),
        ("High", "Alta"),
        ("Urgent", "Urgente"),
        ("Projects", "Proyectos"),
        ("New Project", "Nuevo proyecto"),
        ("Delete Project", "Eliminar proyecto"),
        ("Couldn't load projects", "No se pudieron cargar los proyectos"),
        ("No projects yet", "Aún no hay proyectos"),
        (
            "Projects you create on your Vikunja instance will show up here.",
            "Los proyectos que crees en tu instancia de Vikunja aparecerán aquí.",
        ),
        (
            "This permanently deletes the project, its subprojects, and all their tasks.",
            "Esto elimina el proyecto, sus subproyectos, y todas sus tareas de forma permanente.",
        ),
        (
            "This permanently deletes the project and all its tasks.",
            "Esto elimina el proyecto y todas sus tareas de forma permanente.",
        ),
        ("No tasks", "Sin tareas"),
        ("Collapse", "Contraer"),
        ("Expand", "Expandir"),
        ("Parent Project", "Proyecto padre"),
        ("Project name", "Nombre del proyecto"),
        ("Color", "Color"),
        ("Save", "Guardar"),
        ("Project updated", "Proyecto actualizado"),
        ("Project created", "Proyecto creado"),
        ("Project deleted", "Proyecto eliminado"),
        ("priority.none", "Ninguna"),
        ("%lld/%lld tasks completed", "%lld/%lld tareas completadas"),
        ("%lld/%lld tasks", "%lld/%lld tareas"),
        ("%lld of %lld tasks completed", "%lld de %lld tareas completadas"),
    ])
    func `key resolves to its Spanish translation`(key: String, expected: String) {
        #expect(Self.es(key) == expected)
    }
}
