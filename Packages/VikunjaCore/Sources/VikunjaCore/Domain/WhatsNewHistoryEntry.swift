/// A condensed, hand-written recap of a past release, shown on the "Ver
/// versiones anteriores" timeline. `items` are plain display strings, not
/// `WhatsNewFeature`s — the timeline is a lightweight recap, not a replay
/// of each old release's full content, so there's nothing to merge at
/// runtime when a user skips several releases.
public struct WhatsNewHistoryEntry: Equatable, Sendable, Codable {
    public let version: String
    public let date: String
    public let items: [String]

    public init(version: String, date: String, items: [String]) {
        self.version = version
        self.date = date
        self.items = items
    }
}
