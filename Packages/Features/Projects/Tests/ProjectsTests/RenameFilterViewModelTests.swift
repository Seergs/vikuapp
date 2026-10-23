@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct RenameFilterViewModelTests {
    /// Project id -6 is the pseudo-project id for saved filter 5
    /// (`-id - 1`, see `ProjectKind`).
    private static let filterProject = Project(id: -6, title: "Overdue work")

    @Test
    func `save trims the title and renames through the filter repository with the real filter id`() async {
        let repository = FakeFilterRepository()
        let toastPresenter = FakeToastPresenter()
        let viewModel = RenameFilterViewModel(
            project: Self.filterProject,
            repository: repository,
            toastPresenter: toastPresenter,
        )
        viewModel.title = "  Archived work  "

        let result = await viewModel.save()

        #expect(result == true)
        #expect(repository.renamedTitles == ["Archived work"])
        #expect(toastPresenter.shownMessages.map(\.message) == ["Filter renamed"])
    }

    @Test
    func `can save is false when the title is empty or only whitespace`() {
        let viewModel = RenameFilterViewModel(
            project: Self.filterProject,
            repository: FakeFilterRepository(),
            toastPresenter: FakeToastPresenter(),
        )

        viewModel.title = "   "

        #expect(viewModel.canSave == false)
    }

    @Test
    func `save surfaces an error message when the repository rejects the rename`() async {
        let repository = FakeFilterRepository()
        repository.renameError = .network("offline")
        let viewModel = RenameFilterViewModel(
            project: Self.filterProject,
            repository: repository,
            toastPresenter: FakeToastPresenter(),
        )
        viewModel.title = "Archived work"

        let result = await viewModel.save()

        #expect(result == false)
        #expect(viewModel.saveErrorMessage != nil)
    }
}
