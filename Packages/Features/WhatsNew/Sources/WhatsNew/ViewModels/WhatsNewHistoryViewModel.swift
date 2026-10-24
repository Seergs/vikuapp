import Foundation
import Observation
import VikunjaCore

/// Drives the "See previous versions" timeline. Reads straight from
/// `content.history`, the flat recap array already bundled in the current
/// release's JSON — no merging with past releases' own content, no actions,
/// no icons, just version/date/plain-text items per entry.
@MainActor
@Observable
public final class WhatsNewHistoryViewModel {
    public let entries: [WhatsNewHistoryEntry]

    public init(entries: [WhatsNewHistoryEntry]) {
        self.entries = entries
    }

    /// The entry's date, formatted as an absolute "Oct 23, 2026" — `nil` if
    /// it isn't a valid `yyyy-MM-dd` string, so the view can omit it rather
    /// than show garbage. Same approach as `WhatsNewMainViewModel.dateLabel`.
    public func dateLabel(for entry: WhatsNewHistoryEntry) -> String? {
        Self.dateFormatter.date(from: entry.date).map {
            $0.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
