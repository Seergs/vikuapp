import XCTest

@MainActor
final class AppearanceTests: XCTestCase {
    func testLightDarkAndAutomaticApplyToVisibleUI() {
        continueAfterFailure = false
        let originalAppearance = XCUIDevice.shared.appearance
        let application = UITestApp()
        addTeardownBlock { @MainActor () async in
            application.terminate()
            XCUIDevice.shared.appearance = originalAppearance
            XCTAssertEqual(XCUIDevice.shared.appearance, originalAppearance)
        }
        // Automatic must undo the explicit dark override and inherit the system appearance.
        XCUIDevice.shared.appearance = .light
        application.launch().assertFixtureVisible()
        let appearance = AppPage(app: application.app).showSettings().openAppearance()
        appearance.assertRenderedAppearance(dark: false, name: "Initial automatic appearance")

        appearance.select(.dark)
        appearance.assertRenderedAppearance(dark: true, name: "Dark before explicit light override")
        appearance.select(.light)
        appearance.assertRenderedAppearance(dark: false, name: "Explicit light appearance")
        appearance.select(.dark)
        appearance.assertRenderedAppearance(dark: true, name: "Explicit dark appearance")
        appearance.select(.automatic)
        appearance.assertRenderedAppearance(dark: false, name: "Automatic restores system light appearance")
    }
}
