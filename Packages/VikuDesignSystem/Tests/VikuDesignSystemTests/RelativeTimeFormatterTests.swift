import Foundation
import Testing
@testable import VikuDesignSystem

@MainActor
struct RelativeTimeFormatterTests {
    private let calendar = Calendar.current
    private let reference = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(),
    ) ?? Date()

    @Test
    func `formats a past timestamp relative to the reference`() throws {
        let twoHoursAgo = try #require(calendar.date(byAdding: .hour, value: -2, to: reference))
        let expected = { () -> String in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: twoHoursAgo, relativeTo: reference)
        }()

        #expect(RelativeTimeFormatter.string(for: twoHoursAgo, relativeTo: reference) == expected)
    }
}
