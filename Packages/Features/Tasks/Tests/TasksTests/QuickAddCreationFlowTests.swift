import Foundation
@testable import Tasks
import Testing
import VikunjaCore

/// The original and redesigned sheets share these intents and the save flow.
@MainActor
struct QuickAddCreationFlowTests {
    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `picker changes preserve typed dates and labels through a failed save and retry`(
        syntax: QuickAddSyntax,
    ) async throws {
        let tasks = FakeTaskRepository()
        let projects = FakeProjectRepository()
        let labels = FakeLabelRepository()
        let inbox = Project(id: 1, title: "Inbox")
        let work = Project(id: 2, title: "Work")
        projects.projects = [inbox, work]
        labels.labels = [Label(id: 10, title: "design", hexColor: "6449A2")]
        let viewModel = try QuickAddTaskViewModel(
            accountDefaultProjectID: 1,
            taskRepository: tasks,
            projectRepository: projects,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: syntax),
            labelRepository: labels,
            dateParsingContext: .init(
                referenceDate: Date(timeIntervalSince1970: 1_794_052_800),
                timeZone: #require(TimeZone(secondsFromGMT: 0)),
                languages: [.spanish, .english],
            ),
        )
        await viewModel.load()
        #expect(viewModel.selectedProject == inbox)

        viewModel.input = "Review tomorrow \(syntax.labelSigil)design"
        viewModel.pickProject(work)
        viewModel.pickPriority(.high)
        let draft = viewModel.input
        let dueDate = try #require(viewModel.parsed.dueDate)
        #expect(viewModel.canSave)
        #expect(viewModel.titleHighlights.spans.contains { $0.style == .date })

        tasks.createError = .network("offline")
        #expect(await viewModel.save() == nil)
        #expect(viewModel.input == draft)
        #expect(viewModel.selectedProject == work)
        #expect(viewModel.priority == .high)
        #expect(viewModel.parsed.dueDate == dueDate)
        #expect(viewModel.saveErrorMessage != nil)
        #expect(viewModel.canSave)
        #expect(tasks.tasks.isEmpty)

        tasks.createError = nil
        let created = try #require(await viewModel.save())
        #expect(created.title == "Review")
        #expect(created.projectID == work.id)
        #expect(created.priority == .high)
        #expect(created.dueDate == dueDate)
        #expect(labels.addedLabelIDs.map(\.labelID) == [10])
        #expect(tasks.tasks.count == 1)
        #expect(viewModel.saveErrorMessage == nil)
    }

    @Test func `project and priority pickers work with magic disabled and keep shortcut-like text literal`() async throws {
        let tasks = FakeTaskRepository()
        let projects = FakeProjectRepository()
        let work = Project(id: 2, title: "Work")
        projects.projects = [work]
        let viewModel = QuickAddTaskViewModel(
            taskRepository: tasks,
            projectRepository: projects,
            toastPresenter: FakeToastPresenter(),
            syntaxStore: FakeQuickAddSyntaxStore(syntax: nil),
        )
        await viewModel.load()
        viewModel.input = "Review tomorrow #Work @design p1"
        #expect(!viewModel.canSave)
        viewModel.pickProject(work)
        viewModel.pickPriority(.high)

        let created = try #require(await viewModel.save())
        #expect(created.title == "Review tomorrow #Work @design p1")
        #expect(created.projectID == work.id)
        #expect(created.priority == .high)
        #expect(created.dueDate == nil)
        #expect(viewModel.titleHighlights.spans.isEmpty)
    }
}
