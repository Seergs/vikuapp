import Foundation
import Observation

/// Keeps a drag source hidden across the asynchronous handoff to its drop destination.
@MainActor
@Observable
public final class CardDragPresentation {
    private struct Source {
        let identity: String
        let didRemove: @MainActor () -> Void
    }

    private var hiddenSources: Set<String> = []
    private var activeSource: Source?
    private var pendingDrops: [UUID: Source] = [:]

    public init() {}

    public func isSourceHidden(_ identity: String) -> Bool {
        hiddenSources.contains(identity)
    }

    func beginDrag(source: String, didRemove: @escaping @MainActor () -> Void = {}) {
        activeSource = Source(identity: source, didRemove: didRemove)
        hiddenSources.insert(source)
    }

    func endDrag(source: String, didMove: Bool) {
        if activeSource?.identity == source {
            activeSource = nil
        }
        if !didMove || !pendingDrops.values.contains(where: { $0.identity == source }) {
            hiddenSources.remove(source)
        }
    }

    /// Call synchronously when accepting a drop, before loading its item provider.
    public func beginDrop() -> UUID? {
        guard let activeSource else { return nil }
        let token = UUID()
        pendingDrops[token] = activeSource
        return token
    }

    /// A relocated source must stay hidden through its outgoing SwiftUI transition.
    /// Only a failed or same-column drop should restore that controller's content.
    public func finishDrop(_ token: UUID?, sourceWasRemoved: Bool = false) {
        guard let token, let source = pendingDrops.removeValue(forKey: token) else { return }
        if sourceWasRemoved {
            source.didRemove()
        }
        if activeSource?.identity != source.identity,
           !pendingDrops.values.contains(where: { $0.identity == source.identity }) {
            hiddenSources.remove(source.identity)
        }
    }

    public func reset() {
        activeSource = nil
        pendingDrops.removeAll()
        hiddenSources.removeAll()
    }
}
