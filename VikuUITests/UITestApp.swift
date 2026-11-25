import XCTest

@MainActor
struct UITestApp {
    let app = XCUIApplication()

    @discardableResult
    func launch(preservingPreferences: Bool = false, slowReachability: Bool = false) -> TodayPage {
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if preservingPreferences {
            app.launchArguments.append("-UITestPreservePreferences")
        }
        if slowReachability {
            app.launchArguments.append("-UITestSlowReachability")
        }
        app.launch()
        return TodayPage(app: app)
    }

    func terminate() {
        app.terminate()
    }
}
