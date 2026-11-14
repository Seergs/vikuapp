/// Keeps a presentation coherent while its live source continues to update.
/// A drag can overlap a context menu; only the last interaction releases the snapshot.
@MainActor
final class ContextMenuSession<Value> {
    enum Interaction: Hashable {
        case menu
        case drag
    }

    private(set) var latest: Value
    private var snapshot: Value?
    private var interactions: Set<Interaction> = []

    var isPresented: Bool {
        !interactions.isEmpty
    }

    var displayed: Value {
        snapshot ?? latest
    }

    init(_ value: Value) {
        self.latest = value
    }

    func update(_ value: Value) {
        latest = value
    }

    @discardableResult
    func begin(_ interaction: Interaction) -> Value {
        if !isPresented {
            snapshot = latest
        }
        interactions.insert(interaction)
        return displayed
    }

    func end(_ interaction: Interaction) {
        interactions.remove(interaction)
        if !isPresented {
            snapshot = nil
        }
    }
}
