import XCTest

@MainActor
struct SettingsPage {
    let app: XCUIApplication

    func openAppearance(file: StaticString = #filePath, line: UInt = #line) -> AppearancePage {
        let appearance = app.buttons["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10), file: file, line: line)
        appearance.tap()
        let page = AppearancePage(app: app)
        page.assertVisible(file: file, line: line)
        return page
    }
}
