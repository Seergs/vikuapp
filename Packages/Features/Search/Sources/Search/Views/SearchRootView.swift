import SwiftUI
import VikunjaCore

/// Search's entry point for the app target: the search screen's root content,
/// including its `.searchable` field. The hosting `NavigationStack` and its
/// `AppRouter` are owned by the app target (`MainTabView`); this view reaches
/// navigation through `@Environment(AppRouter.self)` like every other screen.
public struct SearchRootView: View {
    @Bindable public var viewModel: SearchViewModel

    public init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SearchView(viewModel: viewModel)
    }
}
