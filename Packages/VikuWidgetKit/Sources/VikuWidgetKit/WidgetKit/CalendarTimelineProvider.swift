#if canImport(WidgetKit)
import Foundation
import WidgetKit

public struct CalendarEntry: TimelineEntry, Sendable {
    public let date: Date
    public let state: CalendarWidgetState

    public init(date: Date, state: CalendarWidgetState) {
        self.date = date
        self.state = state
    }
}

/// Drives `CalendarWidget`. Each refresh runs `CalendarSnapshotLoader` once and
/// schedules the next one `VikuWidgetConfig.refreshInterval` out — same coarse
/// cadence as `TodayTimelineProvider`; the app nudges
/// `WidgetCenter.reloadAllTimelines()` after a task edit for anything more
/// immediate.
public struct CalendarTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in _: Context) -> CalendarEntry {
        CalendarEntry(date: Date(), state: .content(.placeholder))
    }

    public func getSnapshot(in context: Context, completion: @escaping @Sendable (CalendarEntry) -> Void) {
        if context.isPreview {
            completion(CalendarEntry(date: Date(), state: .content(.placeholder)))
            return
        }
        Task {
            let state = await VikuWidgetEnvironment.makeCalendarSnapshotLoader().loadLocalState() ?? .unavailable
            completion(CalendarEntry(date: Date(), state: state))
        }
    }

    public func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<CalendarEntry>) -> Void) {
        Task {
            let now = Date()
            let state = await VikuWidgetEnvironment.makeCalendarSnapshotLoader().loadState()
            let next = now.addingTimeInterval(VikuWidgetConfig.refreshInterval)
            let timeline = Timeline(entries: [CalendarEntry(date: now, state: state)], policy: .after(next))
            completion(timeline)
        }
    }
}
#endif
