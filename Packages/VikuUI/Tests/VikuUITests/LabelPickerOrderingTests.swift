import Foundation
import Testing
import VikunjaCore
@testable import VikuUI

struct LabelPickerOrderingTests {
    private let first = Label(id: 1, title: "Work", hexColor: "EF4444")
    private let second = Label(id: 2, title: "Personal", hexColor: "EF4444")
    private let third = Label(id: 3, title: "Homework", hexColor: "EF4444")

    @Test(arguments: [true, false])
    func `sync between catalog and task reads produces one selected created row`(catalogIsNewer: Bool) throws {
        let local = Label(id: .local(UUID()), title: "New", hexColor: "EF4444")
        let remote = Label(id: 100, title: "New", hexColor: "ef4444")
        var ordering = LabelPickerOrdering(taskLabels: [])
        ordering.didCreate(local)
        let catalog = LabelCatalog(
            labels: [first, catalogIsNewer ? remote : local], aliases: [local.id: remote.id],
        )
        let items = ordering.items(catalog: catalog, taskLabels: [catalogIsNewer ? local : remote])
        #expect(items.count == 2)
        let created = try #require(items.first)
        #expect(created.label.id == remote.id)
        #expect(created.id == local.id)
        #expect(created.isSelected)
        #expect(created.section == .onTask)
        #expect(items.last?.label == first)
    }

    @Test
    func `sync preserves row identity and opening priority`() throws {
        let local = Label(id: .local(UUID()), title: "New", hexColor: "EF4444")
        let remote = Label(id: 100, title: "New", hexColor: "ef4444")
        let ordering = LabelPickerOrdering(taskLabels: [local])
        let before = ordering.items(catalog: LabelCatalog(labels: [first, local]), taskLabels: [local])
        let after = ordering.items(
            catalog: LabelCatalog(labels: [first, remote], aliases: [local.id: remote.id]), taskLabels: [remote],
        )
        #expect(before.map(\.id) == after.map(\.id))
        #expect(before.map(\.section) == after.map(\.section))
        #expect(try #require(after.first).isSelected)
    }

    @Test
    func `identical label names remain distinct without an identity alias`() {
        let other = Label(id: 100, title: first.title, hexColor: first.hexColor)
        let items = LabelPickerOrdering(taskLabels: [other]).items(
            catalog: LabelCatalog(labels: [first, other]), taskLabels: [other],
        )
        #expect(items.map(\.label.id) == [other.id, first.id])
        #expect(items.map(\.isSelected) == [true, false])
    }

    @Test
    func `sections stay fixed when labels are selected deselected or rolled back`() {
        let ordering = LabelPickerOrdering(taskLabels: [second])
        let catalog = LabelCatalog(labels: [first, second, third])
        for selection in [[second], [third], [], [second, third]] {
            let items = ordering.items(catalog: catalog, taskLabels: selection)
            #expect(items.map(\.label.id) == [second.id, first.id, third.id])
            #expect(items.map(\.section) == [.onTask, .other, .other])
            #expect(items.map(\.isSelected) == [second, first, third].map { selection.contains($0) })
        }
        let searched = ordering.items(catalog: catalog, taskLabels: [third], query: "work")
        #expect(searched.map(\.label.id) == [first.id, third.id])
        #expect(searched.allSatisfy { $0.section == .other })
    }

    @Test
    func `creation appears directly in the first section and stays there after deselection`() {
        var ordering = LabelPickerOrdering(taskLabels: [second])
        let initial = LabelCatalog(labels: [first, second])
        ordering.beginCreation(catalog: initial, taskLabels: [second])
        let updated = LabelCatalog(labels: [first, second, third])
        let pending = ordering.items(catalog: updated, taskLabels: [second, third])
        #expect(pending.map(\.label.id) == [second.id, first.id])
        #expect(ordering.isCreating)

        ordering.finishCreation(third)
        for selection in [[second, third], [second], []] {
            let items = ordering.items(catalog: updated, taskLabels: selection)
            #expect(items.map(\.label.id) == [third.id, second.id, first.id])
            #expect(items.map(\.section) == [.onTask, .onTask, .other])
        }
        #expect(!ordering.isCreating)
    }

    @Test
    func `failed or cancelled creation releases the pending state without promoting a label`() {
        var ordering = LabelPickerOrdering(taskLabels: [second])
        let initial = LabelCatalog(labels: [first, second])
        ordering.beginCreation(catalog: initial, taskLabels: [second])
        ordering.finishCreation(nil)
        #expect(!ordering.isCreating)
        // A successful create with a failed attachment remains available for retry.
        let items = ordering.items(catalog: LabelCatalog(labels: [first, second, third]), taskLabels: [second])
        #expect(items.map(\.label.id) == [second.id, first.id, third.id])
        #expect(items.map(\.section) == [.onTask, .other, .other])
    }

    @Test
    func `opening puts selected labels first and preserves order within each group`() {
        let ordering = LabelPickerOrdering(taskLabels: [third, second])
        #expect(ordering.labels(allLabels: [first, second, third], taskLabels: [third, second])
            == [second, third, first])
    }

    @Test
    func `selection changes and rollbacks do not move existing rows`() {
        let ordering = LabelPickerOrdering(taskLabels: [second])
        let catalog = [first, second, third]
        for selection in [[second], [second, third], [third], [], [second]] {
            #expect(ordering.labels(allLabels: catalog, taskLabels: selection) == [second, first, third])
        }
    }

    @Test
    func `reopening uses the current selection`() {
        let ordering = LabelPickerOrdering(taskLabels: [third])
        #expect(ordering.labels(allLabels: [first, second, third], taskLabels: [third])
            == [third, first, second])
    }

    @Test
    func `attached labels are available before a slow or failed catalog load`() {
        let ordering = LabelPickerOrdering(taskLabels: [second])
        #expect(ordering.labels(allLabels: [], taskLabels: [second]) == [second])
        #expect(ordering.labels(allLabels: [first, second, third], taskLabels: [second])
            == [second, first, third])
    }

    @Test
    func `newly created labels appear first and stay there after deselection`() {
        var ordering = LabelPickerOrdering(taskLabels: [second])
        ordering.didCreate(third)
        ordering.didCreate(first)
        #expect(ordering.labels(allLabels: [second, third, first], taskLabels: [second])
            == [first, third, second])
    }

    @Test
    func `search filters every group without changing the session order`() {
        var ordering = LabelPickerOrdering(taskLabels: [second])
        ordering.didCreate(third)
        let catalog = [first, second, third]
        #expect(ordering.labels(allLabels: catalog, taskLabels: [second], query: " WORK ") == [third, first])
        #expect(ordering.labels(allLabels: catalog, taskLabels: [second], query: "missing").isEmpty)
        #expect(ordering.labels(allLabels: catalog, taskLabels: [second]) == [third, second, first])
    }

    @Test
    func `failed attachment leaves an available label in its ordinary position`() {
        let ordering = LabelPickerOrdering(taskLabels: [second])
        // The creation callback returns nil on failure, so no priority is recorded.
        #expect(ordering.labels(allLabels: [first, second, third], taskLabels: [second])
            == [second, first, third])
    }

    @Test
    func `identity drives grouping and fresh catalog metadata is retained without duplicates`() {
        let ordering = LabelPickerOrdering(taskLabels: [second])
        var refreshed = second
        refreshed.title = "Renamed"
        #expect(ordering.labels(allLabels: [first, refreshed], taskLabels: [second]) == [refreshed, first])
    }
}
