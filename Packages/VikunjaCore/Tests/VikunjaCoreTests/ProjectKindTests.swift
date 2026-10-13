import Testing
@testable import VikunjaCore

@Suite("Project.kind")
struct ProjectKindTests {
    @Test
    func `positive ids are real projects`() {
        #expect(Project(id: 1, title: "Work").kind == .project)
        #expect(Project(id: 42, title: "Inbox").kind == .project)
    }

    @Test
    func `id -1 is Favorites`() {
        #expect(Project(id: -1, title: "Favorites").kind == .favorites)
    }

    @Test
    func `any other negative id is a saved filter`() {
        #expect(Project(id: -2, title: "My Open Tasks").kind == .savedFilter)
        #expect(Project(id: -3, title: "Another filter").kind == .savedFilter)
    }
}
