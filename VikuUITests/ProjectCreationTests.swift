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

        projects.setExpanded(true, project: parent)
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
