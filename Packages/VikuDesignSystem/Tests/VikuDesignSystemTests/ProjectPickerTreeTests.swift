import Testing
@testable import VikuDesignSystem
import VikunjaCore

@Suite("ProjectPickerTree")
struct ProjectPickerTreeTests {
    private func project(_ id: Int, parent: Int? = nil, position: Double = 0, title: String? = nil) -> Project {
        Project(
            id: .remote(id),
            title: title ?? "Project \(id)",
            parentProjectID: parent.map(EntityID.remote),
            position: position,
        )
    }

    @Test
    func `arranges projects into a parent/child tree ordered by position`() {
        let projects = [
            project(1, position: 2),
            project(2, position: 1),
            project(3, parent: 1, position: 2),
            project(4, parent: 1, position: 1),
        ]

        let tree = ProjectPickerTree.tree(from: projects)

        #expect(tree.map(\.id) == [2, 1])
        #expect(tree[1].children.map(\.id) == [4, 3])
    }

    @Test
    func `nests to arbitrary depth`() {
        let projects = [
            project(1),
            project(2, parent: 1),
            project(3, parent: 2),
            project(4, parent: 3),
        ]

        let tree = ProjectPickerTree.tree(from: projects)

        #expect(tree[0].children[0].children[0].children[0].id == 4)
    }

    @Test
    func `drops a project and its whole subtree when excluded`() {
        let projects = [
            project(1),
            project(2, parent: 1),
            project(3, parent: 2),
            project(4),
        ]

        let tree = ProjectPickerTree.tree(from: projects, excludingSubtreeOf: 1)

        #expect(tree.map(\.id) == [4])
    }

    @Test
    func `survives a cyclic parentProjectID`() {
        let projects = [
            project(1, parent: 2),
            project(2, parent: 1),
        ]

        let tree = ProjectPickerTree.tree(from: projects)

        #expect(tree.isEmpty)
    }

    @Test
    func `flatMatches filters by title, case-insensitively, ignoring hierarchy`() {
        let projects = [
            project(1, title: "Work"),
            project(2, parent: 1, title: "Workout plan"),
            project(3, title: "Home"),
        ]

        let matches = ProjectPickerTree.flatMatches(projects, query: "work")

        #expect(matches.map(\.id) == [1, 2])
    }

    @Test
    func `flatMatches honors the excluded subtree`() {
        let projects = [
            project(1, title: "Work"),
            project(2, parent: 1, title: "Work sub"),
        ]

        #expect(ProjectPickerTree.flatMatches(projects, query: "work", excludingSubtreeOf: 1).isEmpty)
    }

    @Test
    func `ancestorIDs walks from a project up to its root`() {
        let projects = [
            project(1),
            project(2, parent: 1),
            project(3, parent: 2),
        ]

        #expect(ProjectPickerTree.ancestorIDs(of: 3, in: projects) == [1, 2])
        #expect(ProjectPickerTree.ancestorIDs(of: 1, in: projects).isEmpty)
        #expect(ProjectPickerTree.ancestorIDs(of: nil, in: projects).isEmpty)
    }
}
