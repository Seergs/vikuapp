import SwiftUI
import VikunjaCore

/// Identifies which related task's detail screen to push, resolved
/// asynchronously via `TaskDetailViewModel.loadRelatedTask(_:)` when a
/// `DependencyRow` is tapped.
struct RelatedTaskDestination: Identifiable, Hashable {
    let task: VikunjaTask
    let project: Project

    var id: Int {
        task.id
    }
}

/// Wraps the type-erased `AnyView` `projectDestination(_:)` builds, computed
/// once at tap time rather than inside the `.navigationDestination(item:)`
/// closure itself. That closure re-runs on every re-render of this screen —
/// unlike `.navigationDestination(for:)`, which keys off a stable value
/// already sitting in the `NavigationPath` and only rebuilds when the path
/// actually changes — and `AnyView` erases the type identity SwiftUI would
/// otherwise use to recognize "this is still the same destination" across
/// those reruns. Rebuilding the `AnyView` (and the `ProjectOverviewViewModel`
/// inside it) fresh each time meant the pushed screen kept getting torn down
/// and remounted from scratch, restarting its `.task { load() }` before it
/// ever finished — an endless-looking spinner. Building it once here and
/// handing the closure the same cached value every time avoids that; the
/// concrete-typed `relatedTaskDestination` above doesn't need this same
/// treatment since it pushes a real `TaskDetailView`, not an `AnyView`.
struct ProjectDestinationBox: Identifiable, Hashable {
    let id: Int
    let content: AnyView

    /// Written by hand: `AnyView` isn't `Hashable`, and identity here only
    /// ever needs to key off `id` anyway.
    static func == (lhs: ProjectDestinationBox, rhs: ProjectDestinationBox) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
