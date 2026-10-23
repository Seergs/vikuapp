import Foundation

/// Abbreviated relative-time phrasing ("2 min. ago", "5 days ago") for timestamps in
/// list rows — comment and attachment metadata lines today. Wraps a single
/// cached `RelativeDateTimeFormatter`; `@MainActor` because that formatter is
/// not `Sendable`.
@MainActor
public enum RelativeTimeFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        // es-MX's CLDR data renders .abbreviated's "day" unit as a bare
        // signed value ("-5 días") no matter the dateTimeStyle; .short
        // doesn't have that quirk and still abbreviates seconds the same way.
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    public static func string(for date: Date, relativeTo reference: Date = Date()) -> String {
        formatter.localizedString(for: date, relativeTo: reference)
    }
}
