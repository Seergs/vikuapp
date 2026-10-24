import SwiftUI

/// The whole "What's New" sheet: a real `NavigationStack` so switching
/// between the main screen and a guide/history screen gets the platform's
/// native push/pop animation (and swipe-back gesture) for free, instead of
/// a hand-rolled `.transition` imitating one. Still entirely local `@State`,
/// never `AppRoute` — see `WhatsNewSheetViewModel`'s doc comment for why.
/// This is the one view whatever presents the sheet (the app's composition
/// root) needs to know about; `WhatsNewMainView`/`WhatsNewGuideView`/
/// `WhatsNewHistoryView` are internal wiring details of this screen.
///
/// `WhatsNewSheetViewModel.screen` stays the single, already-tested source
/// of truth for "which screen" — this view only ever *derives* the stack's
/// path from it (`pathBinding`), it never writes `screen` to push. The only
/// way `pathBinding`'s `set` fires with a change is the system's own
/// swipe-back/back gesture popping the stack, which it forwards to
/// `backToMain()` to keep the two in sync.
public struct WhatsNewSheetView: View {
    @State private var viewModel: WhatsNewSheetViewModel

    /// Takes a factory, not an already-built view model — see
    /// `WhatsNewMainView.init`'s doc comment for why.
    public init(makeViewModel: @escaping () -> WhatsNewSheetViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack(path: pathBinding) {
            WhatsNewMainView(makeViewModel: viewModel.makeMainViewModel)
                .hideNavigationBar()
                .navigationDestination(for: WhatsNewRoute.self) { route in
                    destination(for: route)
                        .hideNavigationBar()
                }
        }
    }

    @ViewBuilder
    private func destination(for route: WhatsNewRoute) -> some View {
        switch route {
        case let .guide(guide):
            WhatsNewGuideView(
                makeViewModel: { viewModel.makeGuideViewModel(for: guide) },
                onBack: viewModel.backToMain,
            )
        case .history:
            WhatsNewHistoryView(
                makeViewModel: viewModel.makeHistoryViewModel,
                onBack: viewModel.backToMain,
            )
        }
    }

    private var pathBinding: Binding<[WhatsNewRoute]> {
        Binding(
            get: {
                switch viewModel.screen {
                case .new: []
                case let .guide(guide): [.guide(guide)]
                case .history: [.history]
                }
            },
            set: { newPath in
                if newPath.isEmpty {
                    viewModel.backToMain()
                }
            },
        )
    }
}

private extension View {
    /// Hides the system navigation bar so each screen's own hand-drawn
    /// header (back chevron + title) is the only one shown — matches
    /// `InstanceSetupView.hideNavigationBar()`'s same `#if os(iOS)` guard,
    /// since this package also targets macOS for portability, and the
    /// underlying API is iOS-only.
    @ViewBuilder
    func hideNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
