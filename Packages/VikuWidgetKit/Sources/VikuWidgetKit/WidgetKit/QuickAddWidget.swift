// `.accessoryCircular` is an iOS Lock Screen / StandBy family; `os(iOS)` keeps
// this out of the macOS build where that family is unavailable.
#if canImport(WidgetKit) && os(iOS)
import SwiftUI
import VikuDesignSystem
import WidgetKit

/// A minimal Lock Screen / StandBy accessory widget: the Viku glyph (with its
/// small "add" cutout, `VikuGlyphMark`) as a one-tap quick-add launcher — the
/// Lock Screen's only affordance now that the plain "Open Viku" `GlyphWidget`
/// has been folded into this one, so Lock Screen and Control Center
/// (`QuickAddControl`) both offer just "Add Task", drawn with the same
/// glyph. Static: no data, no network, never refreshes. Opens via the
/// `viku://quick-add` deep link rather than an App Intent, the same way
/// `TodayWidget` deep-links to `viku://today`. Add `QuickAddWidget()` to the
/// extension's `WidgetBundle`.
public struct QuickAddWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: VikuWidgetConfig.quickAddWidgetKind, provider: QuickAddTimelineProvider()) { _ in
            QuickAddWidgetView()
        }
        .configurationDisplayName("Add Task")
        .description("The Viku glyph as a one-tap shortcut to add a task.")
        .supportedFamilies([.accessoryCircular])
    }
}

public struct QuickAddEntry: TimelineEntry, Sendable {
    public let date: Date

    public init(date: Date) {
        self.date = date
    }
}

/// One fixed entry, never reloaded — the widget has nothing to keep up to date.
public struct QuickAddTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in _: Context) -> QuickAddEntry {
        QuickAddEntry(date: Date())
    }

    public func getSnapshot(in _: Context, completion: @escaping @Sendable (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: Date()))
    }

    public func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<QuickAddEntry>) -> Void) {
        completion(Timeline(entries: [QuickAddEntry(date: Date())], policy: .never))
    }
}

struct QuickAddWidgetView: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // Explicit disc: `AccessoryWidgetBackground` on its own doesn't
                // reliably show on the Lock Screen here, so draw the frosted
                // ring ourselves. Not accentable, so it stays a faint backing
                // rather than a bright fill.
                Circle().fill(.white.opacity(0.16))
                VikuGlyphMark()
                    .widgetAccentable()
                    .frame(width: side * 0.46, height: side * 0.46)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .widgetURL(URL(string: "\(VikuWidgetConfig.urlScheme)://quick-add"))
        .widgetDevBadge(alignment: .bottom, inset: VikuSpacing.sm)
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}

#Preview(as: .accessoryCircular) {
    QuickAddWidget()
} timeline: {
    QuickAddEntry(date: .now)
}
#endif
