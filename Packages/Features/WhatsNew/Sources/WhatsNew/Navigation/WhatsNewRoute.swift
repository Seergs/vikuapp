import VikunjaCore

/// This sheet's own two "pushed" screens, both reached only from the main
/// screen, never from each other — so `WhatsNewSheetView` can drive a real
/// `NavigationStack` with at most one element in its path. Internal, not
/// `AppRoute`: this never crosses a feature boundary (see
/// `WhatsNewSheetViewModel`'s doc comment), the same reasoning every other
/// `Features/<Name>` module's own `Router<Route>` follows.
enum WhatsNewRoute: Hashable {
    case guide(WhatsNewGuide)
    case history
}
