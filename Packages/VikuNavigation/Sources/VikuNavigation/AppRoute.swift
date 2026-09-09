import VikunjaCore

/// The app-wide set of navigation destinations that cross feature boundaries.
///
/// Any feature can push one of these onto whatever `NavigationStack` currently
/// hosts it (via `AppRouter` in the environment); the app target's single
/// `.appDestinations(...)` modifier (applied once per tab stack) is the only
/// place that resolves a case to a concrete screen. Cases carry `VikunjaCore`
/// domain values only, so this enum stays in a package every feature and the
/// app target can import.
///
/// This replaces the per-feature `(VikunjaTask, Project) -> AnyView` /
/// `(Project) -> AnyView` destination closures that used to be threaded through
/// five feature initializers, plus the `...DestinationBox` wrappers that worked
/// around `AnyView` erasing navigation identity (architecture audit F-12).
/// Intra-feature destinations that carry feature-private payload (e.g. a
/// `ProjectNode` tree) still travel through a feature-local `Route` enum on the
/// same stack — see `Router`.
public enum AppRoute: Hashable, Sendable {
    /// A single task's detail screen. Carries the owning `Project` alongside
    /// the task (not just its id) so the detail screen's pill/swatch never
    /// needs a second fetch.
    case taskDetail(VikunjaTask, Project)
    /// A single project's overview, reached from outside the Projects tree
    /// (a task's project pill, today). Seeded from a bare `Project`, so its
    /// "Subprojects" section doesn't render — matching the old
    /// `ProjectOverviewRootView` cross-feature entry point.
    case projectOverview(Project)
}
