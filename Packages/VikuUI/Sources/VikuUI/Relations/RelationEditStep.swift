import VikunjaCore

/// The two steps of adding a relation, matching the design mockup: first
/// pick a relation kind, then pick the other task. Modeled as one
/// `Identifiable` enum (rather than two independent `Bool`s/optionals) so
/// exactly one sheet is ever presented at a time and picking a kind can hand
/// off straight into the task picker. Carries the target task explicitly
/// (rather than assuming a single fixed task) so every screen that offers
/// "add relation" — the task detail overflow menu, or a task row's context
/// menu on Today/a project's task list — can share one flow and one piece of
/// `@State`, mirroring `LabelPickerSheet`'s per-task closures.
public enum RelationEditStep: Identifiable {
    case pickKind(VikunjaTask)
    case pickTask(VikunjaTask, RelationKind)

    public var id: String {
        switch self {
        case let .pickKind(task): "pickKind-\(task.id)"
        case let .pickTask(task, kind): "pickTask-\(task.id)-\(kind.rawValue)"
        }
    }

    /// The task this step's flow will add a relation to.
    public var task: VikunjaTask {
        switch self {
        case let .pickKind(task): task
        case let .pickTask(task, _): task
        }
    }
}
