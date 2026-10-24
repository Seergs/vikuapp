import Foundation
import VikuNavigation
import VikunjaCore

/// Turns a `WhatsNewAction` that bubbled all the way up to `onAction`
/// (see `WhatsNewSheetViewModel`) into a concrete app-level effect: closing
/// the sheet, following a `viku://` deep link, or opening an external URL.
/// `VikunjaCore`'s `WhatsNewAction` doc comment is explicit that deciding
/// what to actually do with a `.deeplink`/`.url` is whatever presents the
/// sheet's job; this is that logic, kept separate from the composition
/// root's wiring so it can be unit tested with fakes instead of a real
/// `DeepLinkRouter`/`openURL`.
///
/// Every dependency is a plain closure rather than a concrete type: parsing
/// a `viku://` URL into a `DeepLink` needs `VikuWidgetKit`'s scheme string,
/// which only the app target has (`DeepLink.init?(url:)` lives there, not in
/// `VikuNavigation`), so that parsing is injected rather than called
/// directly here.
@MainActor
public struct WhatsNewActionDispatcher {
    private let dismissSheet: () -> Void
    private let resolveDeepLink: (URL) -> DeepLink?
    private let openDeepLink: (DeepLink) -> Void
    private let openURL: (URL) -> Void

    public init(
        dismissSheet: @escaping () -> Void,
        resolveDeepLink: @escaping (URL) -> DeepLink?,
        openDeepLink: @escaping (DeepLink) -> Void,
        openURL: @escaping (URL) -> Void,
    ) {
        self.dismissSheet = dismissSheet
        self.resolveDeepLink = resolveDeepLink
        self.openDeepLink = openDeepLink
        self.openURL = openURL
    }

    /// `.guide` is included only because an action with a `guideId` this
    /// release's bundled content doesn't define fails safe by bubbling here
    /// rather than switching screens (see `WhatsNewSheetViewModel`) —
    /// there's nothing to do with it but drop it, since bundled content
    /// can't be hot-fixed after it ships.
    public func dispatch(_ action: WhatsNewAction) {
        switch action {
        case .guide:
            break
        case .dismiss:
            dismissSheet()
        case let .deeplink(_, url):
            // The sheet must be gone before the destination opens, not
            // after, so the user never sees it still covering the screen
            // the deep link navigated to.
            dismissSheet()
            if let link = resolveDeepLink(url) {
                openDeepLink(link)
            }
        case let .url(_, url):
            openURL(url)
        }
    }
}
