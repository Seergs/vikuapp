/// The full "What's New" document for one release — the single JSON file
/// bundled in the app, replaced wholesale each time the maintainer wants to
/// announce something new. See `WhatsNewRelease` for how a release can ship
/// without replacing this file at all, to intentionally show nothing.
public struct WhatsNewContent: Equatable, Sendable, Codable {
    public let schemaVersion: Int
    public let release: WhatsNewRelease
    public let hero: WhatsNewHero?
    public let features: [WhatsNewFeature]
    public let fixes: [String]
    public let guides: [String: WhatsNewGuide]
    public let history: [WhatsNewHistoryEntry]

    public init(
        schemaVersion: Int,
        release: WhatsNewRelease,
        hero: WhatsNewHero? = nil,
        features: [WhatsNewFeature] = [],
        fixes: [String] = [],
        guides: [String: WhatsNewGuide] = [:],
        history: [WhatsNewHistoryEntry] = [],
    ) {
        self.schemaVersion = schemaVersion
        self.release = release
        self.hero = hero
        self.features = features
        self.fixes = fixes
        self.guides = guides
        self.history = history
    }
}
