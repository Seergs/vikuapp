import Observation
import VikunjaCore

/// Drives the whole "What's New" sheet: which of its internal screens is
/// showing, and what happens when either screen's own action gets handled.
///
/// Switching between the main screen and a guide stays entirely inside this
/// view model's `screen` state — never `AppRoute`/`VikuNavigation` — since it
/// never crosses a feature boundary, only this one sheet's own content.
/// `onAction` is the one way anything escapes this module: a `.dismiss`,
/// `.deeplink`, or `.url` action always bubbles there, for whatever presents
/// the sheet to actually act on (closing it, opening a `viku://` link,
/// opening Safari).
@MainActor
@Observable
public final class WhatsNewSheetViewModel {
    public enum Screen: Equatable {
        case new
        case guide(WhatsNewGuide)
        case history
    }

    public let content: WhatsNewContent
    public private(set) var screen: Screen = .new

    private let onAction: (WhatsNewAction) -> Void

    public init(content: WhatsNewContent, onAction: @escaping (WhatsNewAction) -> Void) {
        self.content = content
        self.onAction = onAction
    }

    public func makeMainViewModel() -> WhatsNewMainViewModel {
        WhatsNewMainViewModel(content: content, onAction: handleMainAction, onShowHistory: showHistory)
    }

    public func makeGuideViewModel(for guide: WhatsNewGuide) -> WhatsNewGuideViewModel {
        WhatsNewGuideViewModel(guide: guide, onAction: handleGuideAction)
    }

    public func makeHistoryViewModel() -> WhatsNewHistoryViewModel {
        WhatsNewHistoryViewModel(entries: content.history)
    }

    public func backToMain() {
        screen = .new
    }

    private func showHistory() {
        screen = .history
    }

    /// A `.guide` action whose `guideId` resolves switches screens locally;
    /// anything else (including a `.guide` action referencing an id this
    /// release's content doesn't actually define — bundled content can't be
    /// hot-fixed, so a typo here must fail safe rather than show a blank
    /// screen) bubbles to `onAction` unchanged.
    private func handleMainAction(_ action: WhatsNewAction) {
        if case let .guide(_, guideId) = action, let guide = content.guides[guideId] {
            screen = .guide(guide)
        } else {
            onAction(action)
        }
    }

    private func handleGuideAction(_ action: WhatsNewAction) {
        onAction(action)
    }
}
