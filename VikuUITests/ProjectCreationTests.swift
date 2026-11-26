import XCTest

@MainActor
final class ProjectCreationTests: XCTestCase {
    func testCreateRootProjectAppearsInProjectsTree() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch().assertFixtureVisible()
        let projects = AppPage(app: application.app).showProjects()
        let title = "UI Test: New root"

        let create = projects.createProject()
        create.assertParent("None")
        create.enterName(title)
        create.save().assertProjectVisible(title)
        projects.openProject(title: title).backToProjects().assertProjectVisible(title)
    }

    func testCreatingProjectScrollsToItsRowInALongList() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch(additionalArguments: ["-UITestLongProjectList"]).assertFixtureVisible()
        let projects = AppPage(app: application.app).showProjects()
        let title = "UI Test: Offscreen project"

        let create = projects.createProject()
        create.enterName(title)
        create.save().assertProjectInViewport(title)

        let child = "UI Test: Subproject above"
        let createChild = projects.createProject()
        createChild.selectParent("UI Test Project 7")
        createChild.enterName(child)
        createChild.save().assertProjectInViewport(child, minimumTopMarginFraction: 0.25)
    }

    func testSlowOnlineCreationLeavesListInPlaceAfterServerConfirms() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch(additionalArguments: ["-UITestLongProjectList", "-UITestSlowProjectCreation"])
            .assertFixtureVisible()
        let projects = AppPage(app: application.app).showProjects()
        let title = "UI Test: Repositioned project"

        let create = projects.createProject()
        create.enterName(title)
        _ = create.save()

        let firstProject = application.app.buttons["project.remote.1"]
        XCTAssertTrue(firstProject.isHittable)
        let firstProjectLeavesViewport = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !firstProject.isHittable },
            object: nil,
        )
        firstProjectLeavesViewport.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [firstProjectLeavesViewport], timeout: 7), .completed)

        let confirmedProject = application.app.buttons["project.remote.100"]
        for _ in 0 ..< 5 where !confirmedProject.isHittable {
            application.app.swipeUp()
        }
        XCTAssertTrue(confirmedProject.isHittable)
    }

    func testCreateSubprojectAppearsUnderNewParentAndFollowsItsExpansion() {
        continueAfterFailure = false
        let application = UITestApp()
        defer { application.terminate() }
        application.launch().assertFixtureVisible()
        let projects = AppPage(app: application.app).showProjects()
        let parent = "UI Test: Parent"
        let child = "UI Test: Child"

        let createParent = projects.createProject()
        createParent.assertParent("None")
        createParent.enterName(parent)
        createParent.save().assertProjectVisible(parent)
        let createChild = projects.createSubproject(in: parent)
        createChild.assertParent(parent)
        createChild.enterName(child)
        _ = createChild.save()

        projects.assertChildBelowParent(child, parent: parent)
        projects.captureHierarchy("Expanded new project hierarchy")
        projects.setExpanded(false, project: parent)
        projects.assertProjectAbsent(child)
        projects.assertProjectVisible(parent)
        projects.assertProjectVisible("UI Test Project")
        projects.captureHierarchy("Collapsed parent hides its child")
        projects.setExpanded(true, project: parent)
        projects.assertChildBelowParent(child, parent: parent)
        projects.openProject(title: child).backToProjects().assertChildBelowParent(child, parent: parent)
    }
}
