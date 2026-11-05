import Testing
import VikunjaCore
@testable import VikuUI

struct LabelPickerStateTests {
    private let existing = Label(id: 1, title: "Work", hexColor: "EF4444")
    private let created = Label(id: 2, title: "New", hexColor: "EF4444")

    @Test
    func `a task without an opening section offers available labels until creation succeeds`() {
        var state = LabelPickerState(taskLabels: [])
        let catalog = LabelCatalog(labels: [existing])
        #expect(!state.ordering.hasOnTaskSection)
        #expect(!state.ordering.items(catalog: catalog, taskLabels: [existing]).isEmpty)
        #expect(!state.ordering.hasOnTaskSection)
        state.ordering.beginCreation(catalog: catalog, taskLabels: [existing])
        state.finishCreation(nil)
        #expect(!state.ordering.hasOnTaskSection)
        state.ordering.beginCreation(catalog: catalog, taskLabels: [existing])
        state.finishCreation(created)
        #expect(state.ordering.hasOnTaskSection)
    }

    @Test
    func `creation keeps search and draft visible until success then exits search`() {
        var state = LabelPickerState(taskLabels: [existing])
        state.query = "New"
        state.isSearchPresented = true
        state.ordering.beginCreation(catalog: LabelCatalog(labels: [existing]), taskLabels: [existing])
        // A slow creation may update the catalog before attachment finishes.
        let updated = LabelCatalog(labels: [existing, created])
        #expect(state.ordering.items(catalog: updated, taskLabels: [existing, created], query: state.query).isEmpty)
        #expect(state.query == "New")
        #expect(state.isSearchPresented)

        state.finishCreation(created)

        #expect(state.query.isEmpty)
        #expect(!state.isSearchPresented)
        #expect(!state.ordering.isCreating)
        let items = state.ordering.items(catalog: updated, taskLabels: [existing, created])
        #expect(items.map(\.label.id) == [created.id, existing.id])
        #expect(items.first?.section == .onTask)
        #expect(items.first?.isSelected == true)
    }

    @Test
    func `failure or cancellation preserves the search draft for retry`() {
        var state = LabelPickerState(taskLabels: [])
        state.query = "New"
        state.isSearchPresented = true
        state.ordering.beginCreation(catalog: LabelCatalog(labels: [existing]), taskLabels: [])

        state.finishCreation(nil)

        #expect(state.query == "New")
        #expect(state.isSearchPresented)
        #expect(!state.ordering.isCreating)
        #expect(!state.ordering.hasOnTaskSection)
    }
}
