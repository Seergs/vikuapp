#if canImport(WidgetKit)
import Foundation
import WidgetKit

public struct TodayEntry: TimelineEntry, Sendable {
    public let date: Date
    public let state: TodayWidgetState

    public init(date: Date, state: TodayWidgetState) {
        self.date = date
        self.state = state
    }
}

/// Drives `TodayWidget`. Each refresh runs `TodaySnapshotLoader` once and
/// schedules the next one `VikuWidgetConfig.refreshInterval` out — WidgetKit
/// only grants a bounded number of refreshes per day, so the cadence stays
/// coarse and the app nudges `WidgetCenter.reloadTimelines(ofKind:)` after a
/// task edit for anything more immediate.
public struct TodayTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in _: Context) -> TodayEntry {
        TodayEntry(date: Date(), state: .content(.placeholder))
    }

    public func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        if context.isPreview {
            completion(TodayEntry(date: Date(), state: .content(.placeholder)))
            return
        }
        Task {
            let state = await VikuWidgetEnvironment.makeSnapshotLoader().loadLocalState() ?? .unavailable
            completion(TodayEntry(date: Date(), state: state))
        }
    }

    public func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        Task {
            let now = Date()
            let state = await VikuWidgetEnvironment.makeSnapshotLoader().loadState()
            let next = now.addingTimeInterval(VikuWidgetConfig.refreshInterval)
            let timeline = Timeline(entries: [TodayEntry(date: now, state: state)], policy: .after(next))
            completion(timeline)
        }
    }
}
#endif
