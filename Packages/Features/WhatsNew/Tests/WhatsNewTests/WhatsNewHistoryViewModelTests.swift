import Foundation
import Testing
import VikunjaCore
@testable import WhatsNew

@MainActor
@Suite("WhatsNewHistoryViewModel")
struct WhatsNewHistoryViewModelTests {
    @Test
    func `exposes the entries unchanged, in their given order`() {
        let entries = [
            WhatsNewHistoryEntry(version: "1.4", date: "2026-09-12", items: ["Push notifications"]),
            WhatsNewHistoryEntry(version: "1.3", date: "2026-07-28", items: ["Offline mode", "Multiple servers"]),
        ]
        let viewModel = WhatsNewHistoryViewModel(entries: entries)

        #expect(viewModel.entries == entries)
    }

    @Test
    func `formats a valid entry date as an absolute label`() {
        let entry = WhatsNewHistoryEntry(version: "1.4", date: "2026-09-12", items: [])
        let viewModel = WhatsNewHistoryViewModel(entries: [entry])

        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 12
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let expectedDate = utcCalendar.date(from: components)

        #expect(viewModel.dateLabel(for: entry) == expectedDate?.formatted(.dateTime.month(.abbreviated).day().year()))
    }

    @Test
    func `an unparseable entry date has no label rather than showing garbage`() {
        let entry = WhatsNewHistoryEntry(version: "1.4", date: "not-a-date", items: [])
        let viewModel = WhatsNewHistoryViewModel(entries: [entry])

        #expect(viewModel.dateLabel(for: entry) == nil)
    }
}
