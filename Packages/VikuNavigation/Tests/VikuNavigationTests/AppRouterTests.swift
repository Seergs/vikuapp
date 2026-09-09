import Testing
@testable import VikuNavigation
import VikunjaCore

private enum FeatureRoute: Hashable {
    case overview(Int)
}

@MainActor
struct AppRouterTests {
    private static let task = VikunjaTask(id: 1, title: "Task", projectID: 7)
    private static let project = Project(id: 7, title: "Project")

    @Test
    func `starts with an empty path`() {
        #expect(AppRouter().path.isEmpty)
    }

    @Test
    func `push app route appends to the path`() {
        let router = AppRouter()

        router.push(.taskDetail(Self.task, Self.project))

        #expect(router.path.count == 1)
    }

    @Test
    func `push feature route appends to the same path`() {
        let router = AppRouter()

        router.push(.projectOverview(Self.project))
        router.push(FeatureRoute.overview(7))

        #expect(router.path.count == 2)
    }

    @Test
    func `pop removes the last route`() {
        let router = AppRouter()
        router.push(.taskDetail(Self.task, Self.project))
        router.push(.projectOverview(Self.project))

        router.pop()

        #expect(router.path.count == 1)
    }

    @Test
    func `pop on an empty path is A no op`() {
        let router = AppRouter()

        router.pop()

        #expect(router.path.isEmpty)
    }

    @Test
    func `pop to root clears the path`() {
        let router = AppRouter()
        router.push(.taskDetail(Self.task, Self.project))
        router.push(.projectOverview(Self.project))

        router.popToRoot()

        #expect(router.path.isEmpty)
    }
}
