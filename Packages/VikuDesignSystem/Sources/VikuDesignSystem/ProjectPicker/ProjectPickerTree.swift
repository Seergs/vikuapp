import VikunjaCore

/// A project positioned within its parent/child hierarchy, ready for the
/// picker to render. View-specific projection of `Project`, not a domain
/// model. Mirrors `Features/Projects`' own `ProjectNode`, kept here so every
/// project-picker call site shares one full-depth tree instead of the
/// per-view-model two-level `ProjectGroup` grouping each used to recompute.
/// Public so `HomeSelectionPickerSheet` (Settings) can render the same
/// collapsible hierarchy, not just `ProjectPickerSheet` itself.
public struct ProjectPickerNode: Identifiable, Hashable {
    public let project: Project
    public let children: [ProjectPickerNode]

    public var id: Int {
        project.id
    }
}

/// Pure tree/filter helpers behind `ProjectPickerSheet` — the logic that used
/// to live as a `projectGroups`/`moveProjectGroups` computed property on five
/// different view models, generalized to arbitrary nesting depth. `tree`/
/// `ancestorIDs` are public so any picker needing the same collapsible
/// hierarchy (e.g. `HomeSelectionPickerSheet`) can reuse the algorithm
/// instead of recomputing it; `flatMatches`/`subtreeIDs` stay internal since
/// only `ProjectPickerSheet` searches today.
public enum ProjectPickerTree {
    /// Builds the parent/child tree for `projects`, ordered by `position`
    /// within each level. Guards against a cyclic `parentProjectID`
    /// (malformed server data) by never revisiting a project id on the same
    /// branch. `excludedID`, when set, drops that project **and its whole
    /// subtree** — a project can't be reparented under itself or a
    /// descendant, and a task's move target can't be its current project.
    public static func tree(from projects: [Project], excludingSubtreeOf excludedID: Int? = nil) -> [ProjectPickerNode] {
        let childrenByParentID = Dictionary(grouping: projects, by: \.parentProjectID)

        func nodes(withParentID parentID: Int?, ancestors: Set<Int>) -> [ProjectPickerNode] {
            (childrenByParentID[parentID] ?? [])
                .filter { $0.id != excludedID }
                .sorted { $0.position < $1.position }
                .compactMap { project in
                    guard !ancestors.contains(project.id) else { return nil }
                    return ProjectPickerNode(
                        project: project,
                        children: nodes(withParentID: project.id, ancestors: ancestors.union([project.id])),
                    )
                }
        }

        return nodes(withParentID: nil, ancestors: [])
    }

    /// Every project whose title matches `query`, flattened (search results
    /// drop the hierarchy). Case-insensitive, same matching the bespoke
    /// pickers used. Honors the same `excludedID` subtree exclusion as `tree`.
    static func flatMatches(_ projects: [Project], query: String, excludingSubtreeOf excludedID: Int? = nil) -> [Project] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let excluded = excludedID.map { subtreeIDs(rootedAt: $0, in: projects) } ?? []
        return projects
            .filter { !excluded.contains($0.id) && $0.title.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.position < $1.position }
    }

    /// The chain of parent ids from `projectID` up to its root, so the picker
    /// can pre-expand the branch holding the current selection. Excludes
    /// `projectID` itself. Cycle-safe.
    public static func ancestorIDs(of projectID: Int?, in projects: [Project]) -> Set<Int> {
        guard let projectID else { return [] }
        let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: Set<Int> = []
        var current = byID[projectID]?.parentProjectID
        while let id = current, !result.contains(id), let project = byID[id] {
            result.insert(id)
            current = project.parentProjectID
        }
        return result
    }

    /// `rootID` plus every descendant id, cycle-safe.
    private static func subtreeIDs(rootedAt rootID: Int, in projects: [Project]) -> Set<Int> {
        let childrenByParentID = Dictionary(grouping: projects, by: \.parentProjectID)
        var result: Set<Int> = []

        func visit(_ id: Int) {
            guard result.insert(id).inserted else { return }
            for child in childrenByParentID[id] ?? [] {
                visit(child.id)
            }
        }

        visit(rootID)
        return result
    }
}
