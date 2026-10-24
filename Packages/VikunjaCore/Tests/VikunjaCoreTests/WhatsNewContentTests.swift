import Foundation
import Testing
@testable import VikunjaCore

/// Decodes the exact JSON from `mockup/whats-new.json` (the agreed schema,
/// copied verbatim into `Fixtures/whats-new.json`), not a hand-written
/// minimal payload, so these tests fail the moment the model and the real
/// content shape drift apart.
@Suite("WhatsNewContent Codable")
struct WhatsNewContentTests {
    private func decode() throws -> WhatsNewContent {
        let url = try #require(Bundle.module.url(forResource: "whats-new", withExtension: "json"))
        return try JSONDecoder().decode(WhatsNewContent.self, from: Data(contentsOf: url))
    }

    @Test
    func `decodes release identity and eligibility floor separately`() throws {
        let content = try decode()
        #expect(content.release.version == "1.5")
        #expect(content.release.minAppVersion == "1.5.0")
    }

    @Test
    func `decodes the hero with a guide action`() throws {
        let content = try decode()
        let hero = try #require(content.hero)
        #expect(hero.id == "calendar-widget")
        #expect(hero.action == .guide(label: "How to add it", guideId: "add-calendar-widget"))
    }

    @Test
    func `decodes features with deeplink and url actions`() throws {
        let content = try decode()
        #expect(content.features.count == 3)
        #expect(try content.features[0].action == .deeplink(
            label: "Create a filter",
            url: #require(URL(string: "viku://filters/new")),
        ))
        #expect(try content.features[2].action == .url(
            label: "Read more",
            url: #require(URL(string: "https://viku.app/docs/dependencies")),
        ))
    }

    @Test
    func `decodes fixes as plain strings`() throws {
        let content = try decode()
        #expect(content.fixes.count == 4)
    }

    @Test
    func `decodes a guide keyed by its id, with a dismiss primary action`() throws {
        let content = try decode()
        let guide = try #require(content.guides["add-calendar-widget"])
        #expect(guide.steps.count == 3)
        #expect(guide.primaryAction == .dismiss(label: "Got it"))
        #expect(guide.secondaryAction?.label == "Read the full guide")
    }

    @Test
    func `decodes history as a flat per-release recap, not nested feature content`() throws {
        let content = try decode()
        #expect(content.history.map(\.version) == ["1.4", "1.3", "1.2"])
        #expect(content.history[0].items == [
            "Push notifications via Viku Relay",
            "Automatically synced webhooks",
        ])
    }

    @Test
    func `round-trips through encode and decode`() throws {
        let content = try decode()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let roundTripped = try decoder.decode(WhatsNewContent.self, from: encoder.encode(content))
        #expect(roundTripped == content)
    }
}
