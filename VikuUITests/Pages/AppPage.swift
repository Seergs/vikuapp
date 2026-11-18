import XCTest

/// Navigation shared by Today and project screens; labels use UITestApp's English locale.
@MainActor
struct AppPage {
    let app: XCUIApplication

    func openQuickAdd(file: StaticString = #filePath, line: UInt = #line) -> QuickAddPage {
        let button = app.buttons["quickAdd.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap()
        let page = QuickAddPage(app: app)
        page.assertVisible(file: file, line: line)
        return page
    }

    func showProjects(file: StaticString = #filePath, line: UInt = #line) -> ProjectsPage {
        let tab = app.tabBars.buttons["Projects"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), file: file, line: line)
        tab.tap()
        return ProjectsPage(app: app)
    }

    func showSearch(file: StaticString = #filePath, line: UInt = #line) -> SearchPage {
        let tab = app.tabBars.buttons["Search"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), file: file, line: line)
        tab.tap()
        let page = SearchPage(app: app)
        page.assertVisible(file: file, line: line)
        return page
    }

    func showToday(file: StaticString = #filePath, line: UInt = #line) -> TodayPage {
        let tab = app.tabBars.buttons["Home"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), file: file, line: line)
        tab.tap()
        return TodayPage(app: app)
    }
}
