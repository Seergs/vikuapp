import XCTest

@MainActor
final class ConnectionIdentityTests: XCTestCase {
    func testExistingConnectionKeepsServerFixedAndRenamesWithoutSigningIn() {
        continueAfterFailure = false
        let application = UITestApp()
        addTeardownBlock { @MainActor in application.terminate() }
        application.launch().assertFixtureVisible()
        _ = AppPage(app: application.app).showSettings()
        let app = application.app
        let connections = app.buttons["Change"]
        XCTAssertTrue(connections.waitForExistence(timeout: 5))
        connections.tap()
        let edit = app.buttons["Edit UI Test Account"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let server = app.textFields["https://tasks.yourcompany.com"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        XCTAssertFalse(server.isEnabled)
        XCTAssertEqual(server.value as? String, "https://ui-testing.invalid")
        XCTAssertTrue(app.buttons["connection.reauthenticate"].exists)
        XCTAssertTrue(app.staticTexts["To use another account or server, add a new connection."].exists)
        XCTAssertFalse(app.secureTextFields.element.exists)
        let name = app.textFields["e.g. Office Server"]
        XCTAssertTrue(name.exists)
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(" Renamed")
        app.scrollViews.firstMatch.swipeUp()
        let save = app.buttons["Save Connection"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let renamed = app.buttons["Edit UI Test Account Renamed"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        let reauthenticate = app.buttons["connection.reauthenticate"]
        XCTAssertTrue(reauthenticate.waitForExistence(timeout: 5))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Connection access action"
        before.lifetime = .keepAlways
        add(before)
        reauthenticate.tap()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connection.reauthenticate"].exists)
    }
}
