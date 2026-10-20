/// Distinguishes a real project from the virtual pseudo-projects Vikunja mixes
/// into `/projects`: Favorites (always id `-1`) and saved filters (any other
/// negative id, mapped back to the real filter id as `-id - 1`).
///
/// The API sends no explicit flag for this — verified against a live v2.6.0
/// instance's `Project`/`ProjectReadBody` schema in both v1 and v2, neither
/// has a `kind`/`is_filter` field. The id's sign is the only signal the
/// server gives, so `Project.kind` just reads it.
public enum ProjectKind: Codable, Hashable, Sendable {
    case project
    case favorites
    case savedFilter
}

public extension Sequence<Project> {
    /// Drops Favorites and saved filters, keeping only real projects — the
    /// set valid as a task's project or a project's parent, since neither
    /// pseudo-project can hold a task or a subproject.
    func realProjectsOnly() -> [Project] {
        filter { $0.kind == .project }
    }
}
