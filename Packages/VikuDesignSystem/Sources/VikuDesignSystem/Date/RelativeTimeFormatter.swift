import Foundation

/// Abbreviated relative-time phrasing ("2h ago", "3d ago") for timestamps in
/// list rows — comment and attachment metadata lines today. Wraps a single
/// cached `RelativeDateTimeFormatter`; `@MainActor` because that formatter is
/// not `Sendable`.
@MainActor
public enum RelativeTimeFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    public static func string(for date: Date, relativeTo reference: Date = Date()) -> String {
        formatter.localizedString(for: date, relativeTo: reference)
    }
}
