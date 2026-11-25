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

    static func precedesAmongSiblings(_ lhs: Project, _ rhs: Project) -> Bool {
        switch (lhs.pendingOnlineCreationAt, rhs.pendingOnlineCreationAt) {
        case (.some, .none): return false
        case (.none, .some): return true
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate: return lhsDate < rhsDate
        default:
            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }
            return lhs.id < rhs.id
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(children)
    }
}
