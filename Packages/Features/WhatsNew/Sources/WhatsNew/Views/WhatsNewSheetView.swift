import SwiftUI

/// The whole "What's New" sheet: swaps between the main screen and a guide
/// screen based on `WhatsNewSheetViewModel.screen`, entirely with local
/// `@State` — see that type's doc comment for why this never needs
/// `AppRoute`. This is the one view whatever presents the sheet (the app's
/// composition root) needs to know about; `WhatsNewMainView`/
/// `WhatsNewGuideView` are internal wiring details of this screen.
public struct WhatsNewSheetView: View {
    @State private var viewModel: WhatsNewSheetViewModel

    /// Takes a factory, not an already-built view model — see
    /// `WhatsNewMainView.init`'s doc comment for why.
    public init(makeViewModel: @escaping () -> WhatsNewSheetViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    public var body: some View {
        switch viewModel.screen {
        case .new:
            WhatsNewMainView(makeViewModel: viewModel.makeMainViewModel)
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
}
