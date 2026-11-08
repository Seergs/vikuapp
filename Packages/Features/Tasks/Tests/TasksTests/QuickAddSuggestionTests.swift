import Foundation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct QuickAddSuggestionTests {
    private func makeModel(store: FakeQuickAddSyntaxStore?) -> QuickAddTaskViewModel {
        QuickAddTaskViewModel(
            taskRepository: FakeTaskRepository(),
            projectRepository: FakeProjectRepository(),
            toastPresenter: FakeToastPresenter(),
            syntaxStore: store,
        )
    }

    @Test func `magic off or no syntax store offers no suggestions`() {
        #expect(makeModel(store: nil).suggestions.isEmpty)
        #expect(makeModel(store: FakeQuickAddSyntaxStore(syntax: nil)).suggestions.isEmpty)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `every example is understood by the selected dialect`(syntax: QuickAddSyntax) throws {
        let model = makeModel(store: FakeQuickAddSyntaxStore(syntax: syntax))
        let examples = model.suggestions
        #expect(examples == (syntax == .todoist
                ? ["tomorrow", "#work", "p2", "@design"]
                : ["tomorrow", "+work", "!3", "*design"]))
        let projects = [Project(id: 1, title: "work")]
        let labels = [Label(id: 10, title: "design", hexColor: "6449A2")]
        let parsed = QuickAddParser.parse(
            "Review " + examples.joined(separator: " "),
            projects: projects, labels: labels, syntax: syntax, dateContext: model.dateParsingContext,
        )
        #expect(parsed.title == "Review")
        #expect(parsed.projectID == 1)
        #expect(parsed.priority == .high)
        #expect(parsed.labelIDs == [10])
        #expect(parsed.newLabelNames.isEmpty)
        #expect(try #require(parsed.dateInterpretation.resolvedDate).components.day != nil)
        // Illustrative examples have no side effects on the actual draft.
        #expect(model.input.isEmpty)
        #expect(model.selectedProjectID == nil)
        #expect(model.priority == .unset)
        #expect(model.dueDate == nil)
        #expect(model.selectedLabels.isEmpty)
    }

    @Test(arguments: [QuickAddSyntax.todoist, .vikunja])
    func `typing hides the row and clearing the input brings it back`(syntax: QuickAddSyntax) {
        let model = makeModel(store: FakeQuickAddSyntaxStore(syntax: syntax))
        let examples = model.suggestions
        model.input = "Review"
        #expect(model.suggestions.isEmpty)
        model.input = " "
        #expect(model.suggestions.isEmpty)
        model.input = ""
        #expect(model.suggestions == examples)
    }

    @Test func `suggestions follow syntax changes without recreating the draft`() {
        let store = FakeQuickAddSyntaxStore(syntax: .todoist)
        let model = makeModel(store: store)
        #expect(model.suggestions.contains("p2"))
        store.setSyntax(.vikunja)
        #expect(model.suggestions == ["tomorrow", "+work", "!3", "*design"])
        store.setSyntax(nil)
        #expect(model.suggestions.isEmpty)
        store.setSyntax(.todoist)
        #expect(model.suggestions == ["tomorrow", "#work", "p2", "@design"])
    }
}
