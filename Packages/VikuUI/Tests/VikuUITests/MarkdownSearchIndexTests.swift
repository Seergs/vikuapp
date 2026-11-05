import Testing
@testable import VikuUI

struct MarkdownSearchIndexTests {
    private let index = MarkdownSearchIndex(entries: [
        .init(id: "offline", text: "Usar Viku sin conexión\nSincroniza tus tareas al volver a conectarte."),
        .init(id: "notifications", text: "Notificaciones push\nConfigura los avisos de tus proyectos."),
        .init(id: "shortcuts", text: "Quick-Add Shortcuts\nSet labels and priorities as you type."),
    ])

    @Test(arguments: ["", "  \n\t "])
    func `empty queries show all articles in catalog order`(query: String) {
        #expect(index.matchingIDs(query: query) == ["offline", "notifications", "shortcuts"])
    }

    @Test(arguments: ["conexion", "CONEXIÓN", "  Conexión  "])
    func `search ignores case accents and surrounding whitespace`(query: String) {
        #expect(index.matchingIDs(query: query) == ["offline"])
    }

    @Test
    func `matches content beyond the title`() {
        #expect(index.matchingIDs(query: "priorities") == ["shortcuts"])
    }

    @Test
    func `all search words must match regardless of order`() {
        #expect(index.matchingIDs(query: "tareas SINCRONIZA") == ["offline"])
        #expect(index.matchingIDs(query: "tareas proyectos").isEmpty)
    }

    @Test
    func `unknown queries return no results`() {
        #expect(index.matchingIDs(query: "calendar").isEmpty)
    }

    @Test
    func `clearing a query restores the full list`() {
        #expect(index.matchingIDs(query: "avisos") == ["notifications"])
        #expect(index.matchingIDs(query: "") == ["offline", "notifications", "shortcuts"])
    }
}
