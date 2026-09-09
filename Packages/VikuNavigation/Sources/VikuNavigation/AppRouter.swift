import Observation
import SwiftUI

/// The navigation state for one tab's `NavigationStack`. The app target creates
/// one per tab, binds the tab's `NavigationStack(path:)` to `path`, and puts it
/// in the environment; any descendant view - however deep, and across feature
/// module boundaries - reads `@Environment(AppRouter.self)` and calls `push`
/// to navigate.
///
/// This is the single cross-feature navigation mechanism (architecture audit
/// F-12). A feature that also has destinations which never leave it keeps its
/// own `Route` enum and pushes those values onto this same path via the
/// generic `push(_:)`; its own `.navigationDestination(for: Route.self)` on the
/// stack resolves them. `Router<Route>` remains for a feature whose entire
/// stack is self-contained (Settings).
@Observable
@MainActor
public final class AppRouter {
    public var path = NavigationPath()

    public init() {}

    /// Navigate to a cross-feature destination. Resolved by the app target's
    /// `.appDestinations(...)` modifier on the hosting stack.
    public func push(_ route: AppRoute) {
        path.append(route)
    }

    /// Navigate to a feature-local destination, resolved by that feature's own
    /// `.navigationDestination(for:)` on the same stack. For routes whose
    /// payload is a feature-private type and so can't live in `AppRoute`.
    public func push(_ route: some Hashable) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    public func popToRoot() {
        path = NavigationPath()
    }
}
