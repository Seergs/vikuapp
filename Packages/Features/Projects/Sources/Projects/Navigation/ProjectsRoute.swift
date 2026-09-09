import VikunjaCore

/// Destinations pushable within the Projects tab that never leave the feature.
/// Carries the whole `ProjectNode` (not just the `Project`) so a project
/// overview's "Subprojects" section, and further drill-down into one of those,
/// needs no second project fetch - a feature-private payload, which is why this
/// stays a feature-local route rather than an `AppRoute` case.
///
/// Pushed onto the tab's shared `AppRouter` path and resolved by
/// `ProjectsRootView`'s own `.navigationDestination(for: ProjectsRoute.self)`.
/// Cross-feature destinations (a task's detail screen) go through `AppRoute`.
public enum ProjectsRoute: Hashable, Sendable {
    case projectOverview(ProjectNode)
}
