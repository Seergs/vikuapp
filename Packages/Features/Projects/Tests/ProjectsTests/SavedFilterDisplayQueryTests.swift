import Foundation
@testable import Projects
import Testing
import VikunjaCore

@MainActor
struct SavedFilterDisplayQueryTests {
    private let rawQuery = "project in 3, 999 && labels = 7 && priority >= 3"

    private struct Fixture {
        let viewModel: ProjectOverviewViewModel
        let projects: FakeProjectRepository
        let labels: FakeLabelRepository
        let filters: FakeFilterRepository
        let toast: FakeToastPresenter
    }

    private func fixture() -> Fixture {
        let projects = FakeProjectRepository()
        projects.projects = [Project(id: 3, title: "Work")]
        let labels = FakeLabelRepository()
        labels.labels = [Label(id: 7, title: "Urgent", hexColor: "")]
        let filters = FakeFilterRepository()
        filters.filter = SavedFilterDetail(
            id: 5, title: "Work filter", description: "", isFavorite: false, query: rawQuery,
        )
        let toast = FakeToastPresenter()
        let tasks = FakeTaskRepository()
        let viewModel = ProjectOverviewViewModel(
            syncTrigger: TestScreenSync(), localData: TestScreenSync(),
            project: Project(id: -6, title: "Work filter"),
            repository: tasks, bulkUpdateRepository: tasks,
            projectRepository: projects, labelRepository: labels,
            relationRepository: FakeTaskRelationRepository(), filterRepository: filters,
            toastPresenter: toast, taskSortStore: FakeTaskSortStore(),
        )
        return Fixture(viewModel: viewModel, projects: projects, labels: labels, filters: filters, toast: toast)
    }

    @Test(arguments: [false, true], [false, true])
    func `catalog failures independently fall back to IDs without failing the screen`(
        projectsFail: Bool, labelsFail: Bool,
    ) async {
        let context = fixture()
        context.projects.fetchError = projectsFail ? .network("offline") : nil
        context.labels.fetchError = labelsFail ? .network("offline") : nil

        await context.viewModel.load()

        let project = projectsFail ? "3" : "Work"
        let label = labelsFail ? "7" : "Urgent"
        #expect(context.viewModel.savedFilterDisplayQuery
            == "project in \(project), 999 && labels = \(label) && priority >= 3")
        #expect(context.viewModel.savedFilterQuery == rawQuery)
        #expect(context.filters.filter.query == rawQuery)
        let highlightedNames = context.viewModel.savedFilterDisplaySegments.filter(\.isResolvedName).map(\.text)
        #expect(highlightedNames == (projectsFail ? [] : ["Work"]) + (labelsFail ? [] : ["Urgent"]))
        #expect(context.viewModel.loadState == .loaded)
        #expect(context.toast.shownMessages.isEmpty)
    }

    @Test func `reload resolves newly available names and current local renames`() async {
        let context = fixture()
        context.projects.projects = []
        context.labels.labels = []
        await context.viewModel.load()
        #expect(context.viewModel.savedFilterDisplayQuery == rawQuery)

        context.projects.projects = [
            Project(id: 3, title: "Renamed Work"), Project(id: .local(UUID()), title: "Unsynced"),
        ]
        context.labels.labels = [Label(id: 7, title: "Renamed Urgent", hexColor: "")]
        await context.viewModel.load()

        #expect(context.viewModel.savedFilterDisplayQuery
            == "project in \"Renamed Work\", 999 && labels = \"Renamed Urgent\" && priority >= 3")
        #expect(context.viewModel.savedFilterQuery == rawQuery)
    }

    @Test func `slow refresh retains the previous display until catalogs finish`() async {
        let context = fixture()
        await context.viewModel.load()
        let previous = context.viewModel.savedFilterDisplayQuery
        let gate = FilterCatalogReadGate()
        context.labels.beforeFetchLabels = { await gate.blockFirstRead() }
        context.projects.projects = [Project(id: 3, title: "Renamed")]

        let refresh = Task { await context.viewModel.load() }
        await gate.waitForRead()
        #expect(context.viewModel.savedFilterDisplayQuery == previous)
        #expect(context.viewModel.loadState == .loaded)
        await gate.release()
        await refresh.value

        #expect(context.viewModel.savedFilterDisplayQuery
            == "project in Renamed, 999 && labels = Urgent && priority >= 3")
    }

    @Test func `cancelled catalog read cannot replace the visible query`() async {
        let context = fixture()
        await context.viewModel.load()
        let previous = context.viewModel.savedFilterDisplayQuery
        let gate = FilterCatalogReadGate()
        context.labels.beforeFetchLabels = { await gate.blockFirstRead() }
        context.filters.filter = SavedFilterDetail(
            id: 5, title: "Changed", description: "", isFavorite: false, query: "labels = 9",
        )

        let refresh = Task { await context.viewModel.load() }
        await gate.waitForRead()
        refresh.cancel()
        await gate.release()
        await refresh.value

        #expect(context.viewModel.savedFilterDisplayQuery == previous)
        #expect(context.viewModel.savedFilterQuery == rawQuery)
    }

    @Test func `stale catalog read cannot overwrite a newer load`() async {
        let context = fixture()
        let gate = FilterCatalogReadGate()
        context.labels.beforeFetchLabels = { await gate.blockFirstRead() }
        let first = Task { await context.viewModel.load() }
        await gate.waitForRead()

        context.filters.filter = SavedFilterDetail(
            id: 5, title: "Changed", description: "", isFavorite: false, query: "project = 3",
        )
        await context.viewModel.load()
        await gate.release()
        await first.value

        #expect(context.viewModel.savedFilterDisplayQuery == "project = Work")
        #expect(context.viewModel.savedFilterQuery == "project = 3")
    }

    @Test func `empty query and failed filter fetch clear previous presentation`() async {
        let context = fixture()
        await context.viewModel.load()
        context.filters.fetchError = .network("offline")
        await context.viewModel.load()
        #expect(context.viewModel.savedFilterDisplayQuery == nil)
        #expect(context.viewModel.savedFilterDisplaySegments.isEmpty)

        context.filters.fetchError = nil
        context.filters.filter = SavedFilterDetail(
            id: 5, title: "Empty", description: "", isFavorite: false, query: "",
        )
        await context.viewModel.load()
        #expect(context.viewModel.savedFilterDisplayQuery == nil)
        #expect(context.viewModel.savedFilterDisplaySegments.isEmpty)
    }
}

private actor FilterCatalogReadGate {
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var suspended: CheckedContinuation<Void, Never>?

    func blockFirstRead() async {
        guard !entered else { return }
        entered = true
        await withCheckedContinuation { continuation in
            suspended = continuation
            arrival?.resume()
            arrival = nil
        }
    }

    func waitForRead() async {
        guard !entered else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}
