@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct EditProjectViewModelTests {
    @Test(arguments: [EntityID.remote(2), .remote(3), nil] as [EntityID?])
    func `saving uses the cached position whether the parent changes or not`(parentID: EntityID?) async throws {
        let project = Project(id: 1, title: "Original", parentProjectID: 2, position: 70)
        var cached = project
        cached.position = 90
        cached.isFavorite = true
        let repository = FakeProjectRepository()
        repository.projects = [cached]
        let viewModel = EditProjectViewModel(
            project: project, repository: repository, toastPresenter: FakeToastPresenter(),
        )
        viewModel.title = "Updated"
        viewModel.hexColor = "FF0000"
        viewModel.parentProjectID = parentID

        let saved = try #require(await viewModel.save())

        #expect(saved.title == "Updated")
        #expect(saved.hexColor == "FF0000")
        #expect(saved.parentProjectID == parentID)
        #expect(saved.position == 90)
        #expect(saved.isFavorite)
    }
}
