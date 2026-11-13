import Foundation
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

    @Test
    func `disabled move destination retains selectable children and grandchildren`() {
        let projects = [project(1), project(2, parent: 1), project(3, parent: 2), project(4)]
        let tree = ProjectPickerTree.tree(from: projects, disablingSelectionOf: 1)

        #expect(tree.map(\.id) == [1, 4])
        #expect(!tree[0].isSelectable)
        #expect(tree[0].children[0].id == 2)
        #expect(tree[0].children[0].isSelectable)
        #expect(tree[0].children[0].children[0].id == 3)
        #expect(tree[0].children[0].children[0].isSelectable)
        #expect(tree[1].isSelectable)
    }

    @Test
    func `search preserves disabled current project and selectable descendants`() {
        let projects = [
            project(1, title: "Work"),
            project(2, parent: 1, title: "Work child"),
            project(3, parent: 2, title: "Work grandchild"),
        ]
        let matches = ProjectPickerTree.flatMatches(projects, query: "work", disablingSelectionOf: 1)

        #expect(matches.map(\.id) == [1, 2, 3])
        #expect(matches.map(\.isSelectable) == [false, true, true])
        #expect(ProjectPickerTree.flatMatches(projects, query: "grandchild", disablingSelectionOf: 1)
            .map(\.id) == [3])
        #expect(ProjectPickerTree.flatMatches(projects, query: "work", excludingSubtreeOf: 1).isEmpty)
    }

    @Test
    func `local project selection can be disabled without excluding its child`() {
        let parent = Project(id: .local(UUID()), title: "Local parent")
        let child = Project(id: .local(UUID()), title: "Local child", parentProjectID: parent.id)
        let projects = [parent, child]
        let tree = ProjectPickerTree.tree(from: projects, disablingSelectionOf: parent.id)
        let matches = ProjectPickerTree.flatMatches(projects, query: "Local", disablingSelectionOf: parent.id)

        #expect(!tree[0].isSelectable)
        #expect(tree[0].children[0].id == child.id)
        #expect(tree[0].children[0].isSelectable)
        #expect(matches.map(\.isSelectable) == [false, true])
        #expect(ProjectPickerTree.tree(from: projects, excludingSubtreeOf: parent.id).isEmpty)
    }
}
