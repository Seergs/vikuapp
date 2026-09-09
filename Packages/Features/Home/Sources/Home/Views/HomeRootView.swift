import SwiftUI
import VikunjaCore

/// Home's entry point for the app target: the Today screen's root content.
/// The hosting `NavigationStack` and its `AppRouter` are owned by the app
/// target (`MainTabView`); this view reaches navigation through
/// `@Environment(AppRouter.self)` like every other screen.
public struct HomeRootView: View {
    private let viewModel: TodayViewModel

    public init(viewModel: TodayViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TodayView(viewModel: viewModel)
    }
}
