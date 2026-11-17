import XCTest

@MainActor
struct UITestApp {
    let app = XCUIApplication()

    @discardableResult
    func launch() -> TodayPage {
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return TodayPage(app: app)
    }

    func terminate() {
        app.terminate()
    }
}
