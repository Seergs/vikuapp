import VikunjaCore

/// A project positioned within its parent/child hierarchy, ready for display.
/// View-specific projection of `Project` — not a domain model itself. Hashable
/// so it can travel through a `NavigationPath` (see `ProjectsRoute`) carrying
/// its own children along, letting a pushed overview screen build its
/// "Subprojects" section without a second fetch.
public struct ProjectNode: Identifiable, Hashable, Sendable {
    public let project: Project
    public let children: [ProjectNode]

    public var id: EntityID {
        project.id
    }

    public init(project: Project, children: [ProjectNode] = []) {
        self.project = project
        self.children = children
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(children)
    }
}
