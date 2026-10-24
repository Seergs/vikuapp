import Foundation
import Testing
import VikunjaCore
@testable import WhatsNew

@MainActor
@Suite("WhatsNewMainViewModel")
struct WhatsNewMainViewModelTests {
    private func content(
        hero: WhatsNewHero? = nil,
        features: [WhatsNewFeature] = [],
        fixes: [String] = [],
        date: String = "2026-10-23",
    ) -> WhatsNewContent {
        WhatsNewContent(
            schemaVersion: 1,
            release: WhatsNewRelease(
                version: "1.5",
                date: date,
                minAppVersion: "1.5.0",
                title: "What's New in Viku",
                subtitle: "Subtitle",
            ),
            hero: hero,
            features: features,
            fixes: fixes,
        )
    }

    @Test
    func `exposes the release hero features and fixes from the content`() {
        let hero = WhatsNewHero(id: "hero", title: "Hero", body: "Hero body")
        let feature = WhatsNewFeature(id: "f1", icon: "star", tint: "blue", title: "Feature", body: "Feature body")
        let testContent = content(hero: hero, features: [feature], fixes: ["Fix 1"])
        let viewModel = WhatsNewMainViewModel(content: testContent) { _ in }

        #expect(viewModel.release.version == "1.5")
        #expect(viewModel.hero?.id == "hero")
        #expect(viewModel.features.map(\.id) == ["f1"])
        #expect(viewModel.fixes == ["Fix 1"])
    }

    @Test
    func `fixes start collapsed and toggle on request`() {
        let viewModel = WhatsNewMainViewModel(content: content()) { _ in }
        #expect(viewModel.isFixesExpanded == false)

        viewModel.toggleFixesExpanded()
        #expect(viewModel.isFixesExpanded == true)

        viewModel.toggleFixesExpanded()
        #expect(viewModel.isFixesExpanded == false)
    }

    @Test
    func `handling an action forwards it to the caller unchanged`() {
        var received: WhatsNewAction?
        let viewModel = WhatsNewMainViewModel(content: content()) { received = $0 }

        viewModel.handle(.dismiss(label: "Got it"))

        #expect(received == .dismiss(label: "Got it"))
    }

    @Test
    func `formats a valid release date as an absolute label`() {
        let viewModel = WhatsNewMainViewModel(content: content(date: "2026-10-23")) { _ in }

        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 23
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let expectedDate = utcCalendar.date(from: components)

        #expect(viewModel.dateLabel == expectedDate?.formatted(.dateTime.month(.abbreviated).day().year()))
    }

    @Test
    func `an unparseable release date has no label rather than showing garbage`() {
        let viewModel = WhatsNewMainViewModel(content: content(date: "not-a-date")) { _ in }
        #expect(viewModel.dateLabel == nil)
    }
}
