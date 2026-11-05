import Foundation
import VikunjaCore

/// Presentation priorities belong to one sheet session, independent of live selection.
struct LabelPickerOrdering {
    private let initiallySelectedIDs: Set<EntityID>
    private var createdIDs: [EntityID] = []
    private var visibleIDsBeforeCreation: Set<EntityID>?

    var isCreating: Bool {
        visibleIDsBeforeCreation != nil
    }

    var hasOnTaskSection: Bool {
        !initiallySelectedIDs.isEmpty || !createdIDs.isEmpty
    }

    init(taskLabels: [Label]) {
        self.initiallySelectedIDs = Set(taskLabels.map(\.id))
    }

    mutating func didCreate(_ label: Label) {
        createdIDs.removeAll { $0 == label.id }
        createdIDs.insert(label.id, at: 0)
    }

    mutating func beginCreation(catalog: LabelCatalog, taskLabels: [Label]) {
        visibleIDsBeforeCreation = Set(labels(
            allLabels: catalog.labels, taskLabels: taskLabels, aliases: catalog.aliases,
        ).map(\.id))
    }

    mutating func finishCreation(_ label: Label?) {
        if let label {
            didCreate(label)
        }
        visibleIDsBeforeCreation = nil
    }

    func items(
        catalog: LabelCatalog, taskLabels: [Label], query: String = "",
    ) -> [LabelPickerItem] {
        let selected = Set(taskLabels.map { catalog.canonicalID(for: $0.id) })
        let onTaskIDs = Set((Array(initiallySelectedIDs) + createdIDs).map { catalog.canonicalID(for: $0) })
        let visibleIDs = visibleIDsBeforeCreation.map { ids in Set(ids.map { catalog.canonicalID(for: $0) }) }
        return labels(
            allLabels: catalog.labels, taskLabels: taskLabels, query: query, aliases: catalog.aliases,
        ).filter { visibleIDs?.contains($0.id) ?? true }.map { label in
            LabelPickerItem(
                id: catalog.stableID(for: label.id), label: label, isSelected: selected.contains(label.id),
                section: onTaskIDs.contains(label.id) ? .onTask : .other,
            )
        }
    }

    func labels(
        allLabels: [Label], taskLabels: [Label], query: String = "",
        aliases: [EntityID: EntityID] = [:],
    ) -> [Label] {
        let catalog = LabelCatalog(labels: allLabels, aliases: aliases)
        let selectedIDs = Set(initiallySelectedIDs.map { catalog.canonicalID(for: $0) })
        var seenCreated = Set<EntityID>()
        let newIDs = createdIDs.map { catalog.canonicalID(for: $0) }.filter { seenCreated.insert($0).inserted }
        var seen = Set<EntityID>()
        // Attached labels are usable even before the catalog finishes loading or if it fails.
        let available = (allLabels + taskLabels)
            .map { catalog.canonicalLabel($0) }
            .filter { seen.insert($0.id).inserted }
        let created = newIDs.compactMap { id in available.first { $0.id == id } }
        let remaining = available.filter { !newIDs.contains($0.id) }
        let ordered = created
            + remaining.filter { selectedIDs.contains($0.id) }
            + remaining.filter { !selectedIDs.contains($0.id) }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? ordered : ordered.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

struct LabelPickerItem: Identifiable {
    let id: EntityID
    let label: Label
    let isSelected: Bool
    let section: Section

    enum Section {
        case onTask
        case other
    }
}
