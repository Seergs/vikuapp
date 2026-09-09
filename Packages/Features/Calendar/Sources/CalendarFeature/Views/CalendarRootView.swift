import SwiftUI
import VikunjaCore

/// Calendar's entry point for the app target: the month-grid screen's root
/// content. The hosting `NavigationStack` and its `AppRouter` are owned by the
/// app target (`MainTabView`); this view reaches navigation through
/// `@Environment(AppRouter.self)` like every other screen.
public struct CalendarRootView: View {
    private let viewModel: CalendarViewModel

    public init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CalendarView(viewModel: viewModel)
    }
}
