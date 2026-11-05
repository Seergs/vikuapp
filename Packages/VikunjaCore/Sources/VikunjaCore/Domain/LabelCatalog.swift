/// Labels and their local-to-current identity mapping, read from one snapshot.
/// The mapping keeps a label recognizable when synchronization assigns a server ID.
public struct LabelCatalog: Sendable {
    public var labels: [Label]
    public let aliases: [EntityID: EntityID]

    public init(labels: [Label], aliases: [EntityID: EntityID] = [:]) {
        self.labels = labels
        self.aliases = aliases
    }

    public func canonicalID(for id: EntityID) -> EntityID {
        aliases[id] ?? id
    }

    public func stableID(for id: EntityID) -> EntityID {
        let canonical = canonicalID(for: id)
        return aliases.first { $0.value == canonical }?.key ?? canonical
    }

    public func canonicalLabel(_ label: Label) -> Label {
        let id = canonicalID(for: label.id)
        return labels.first { $0.id == id }
            ?? Label(id: id, title: label.title, hexColor: label.hexColor)
    }
}
