import XCTest

@MainActor
struct ProjectsPage {
    let app: XCUIApplication

    private func projectRow(_ title: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'project.' AND label == %@", title))
    }

    func createProject(file: StaticString = #filePath, line: UInt = #line) -> CreateProjectPage {
        let create = app.buttons["projects.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), file: file, line: line)
        create.tap()
        let page = CreateProjectPage(app: app)
        page.assertVisible(file: file, line: line)
        return page
    }

    func assertProjectVisible(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(projectRow(title).firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(projectRow(title).count, 1, file: file, line: line)
    }

    func assertProjectAbsent(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(projectRow(title).firstMatch.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    func createSubproject(in parent: String, file: StaticString = #filePath, line: UInt = #line) -> CreateProjectPage {
        let row = projectRow(parent).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
        row.press(forDuration: 1)
        let add = app.buttons["project.addSubproject"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), file: file, line: line)
        add.tap()
        let page = CreateProjectPage(app: app)
        page.assertVisible(file: file, line: line)
        return page
    }

    func setExpanded(_ expanded: Bool, project title: String, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = projectRow(title).firstMatch.buttons.matching(
            NSPredicate(format: "identifier ENDSWITH '.expand'"),
        ).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(toggle.label, expanded ? "Expand" : "Collapse", file: file, line: line)
        toggle.tap()
        XCTAssertTrue(
            toggle.wait(for: \.label, toEqual: expanded ? "Collapse" : "Expand", timeout: 5),
            file: file,
            line: line,
        )
    }

    func assertChildBelowParent(_ child: String, parent: String, file: StaticString = #filePath, line: UInt = #line) {
        assertProjectVisible(child, file: file, line: line)
        assertProjectVisible(parent, file: file, line: line)
        XCTAssertGreaterThan(
            projectRow(child).firstMatch.frame.minY,
            projectRow(parent).firstMatch.frame.minY,
            file: file,
            line: line,
        )
    }

    func captureHierarchy(_ name: String) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func openProject(title: String, file: StaticString = #filePath, line: UInt = #line) -> ProjectPage {
        assertProjectVisible(title, file: file, line: line)
        projectRow(title).firstMatch.tap()
        let page = ProjectPage(app: app, title: title)
        page.assertVisible(file: file, line: line)
        return page
    }

    func openProject(id: Int, title: String, file: StaticString = #filePath, line: UInt = #line) -> ProjectPage {
        let row = app.descendants(matching: .any).matching(identifier: "project.remote.\(id)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
        row.tap()
        let page = ProjectPage(app: app, title: title)
        page.assertVisible(file: file, line: line)
        return page
    }
}

@MainActor
struct ProjectPage {
    let app: XCUIApplication
    let title: String

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), file: file, line: line)
    }

    func assertTaskVisible(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(taskTitle(title).firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(taskTitle(title).count, 1, file: file, line: line)
    }

    func assertTaskAbsent(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(taskTitle(title).firstMatch.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    private func taskTitle(_ title: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier ENDSWITH '.title'", title))
    }

    func backToProjects(file: StaticString = #filePath, line: UInt = #line) -> ProjectsPage {
        let back = app.navigationBars.buttons["Projects"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), file: file, line: line)
        back.tap()
        return ProjectsPage(app: app)
    }
}
