import Foundation

/// An interaction already reloads its source widget when perform() returns.
/// Batch cross-widget requests until accepted writes and their bounded uploads
/// finish; local acceptance and sync callbacks must not issue duplicate reloads.
public actor WidgetTimelineReloads {
    private var interactions: Set<UUID> = []
    private var sourceKinds: Set<String> = []
    private var needsReload = false
    private let taskKinds: Set<String> = [VikuWidgetConfig.todayWidgetKind, VikuWidgetConfig.calendarWidgetKind]
    private let reload: @Sendable (Set<String>) async -> Void

    public init(reload: @escaping @Sendable (Set<String>) async -> Void) {
        self.reload = reload
    }

    public func request() async {
        guard interactions.isEmpty else { needsReload = true; return }
        await reload(taskKinds)
    }

    public func duringInteraction(
        sourceKind: String? = nil, _ operation: @Sendable () async throws -> Void,
    ) async throws {
        let id = UUID()
        interactions.insert(id)
        sourceKinds.insert(sourceKind ?? "")
        do {
            try await operation()
            await finish(id)
        } catch {
            // A failed intent has no guaranteed automatic source reload.
            sourceKinds.insert("")
            await finish(id)
            throw error
        }
    }

    private func finish(_ id: UUID) async {
        interactions.remove(id)
        guard interactions.isEmpty else { return }
        let sources = sourceKinds
        sourceKinds.removeAll()
        guard needsReload else { return }
        needsReload = false
        // All families of one successful source kind reload automatically.
        // Mixed/unknown origins reload both: an earlier source may have already
        // regenerated before a later, overlapping interaction committed.
        let kinds = sources.count == 1 ? taskKinds.subtracting(sources) : taskKinds
        await reload(kinds)
    }
}
