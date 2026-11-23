import AppIntents
import VikuNavigation

/// Opens the quick-add task sheet for shortcuts that explicitly request it.
///
/// Lives in the app target, not `VikuWidgetKit`: an App Intent type that
/// ends up registered in both the app and the widget extension breaks Siri's
/// App Shortcut dispatch ("something went wrong"). The Control Center control
/// uses its own `QuickAddControlIntent` in the extension instead.
///
/// `openAppWhenRun` is true, so `perform()` runs in the app's process and hands
/// off through `DeepLinkRouter.shared` — the same route a `viku://quick-add`
/// URL takes.
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Add"
    static let description = IntentDescription("Opens Viku's quick-add sheet to jot down a new task.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.open(.quickAdd(projectID: nil))
        return .result()
    }
}
