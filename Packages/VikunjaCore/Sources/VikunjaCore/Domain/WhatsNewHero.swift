/// The optional headline feature shown first in a "What's New" release, with
/// its own image and badge. Not every release has one — a release with only
/// minor features or fixes omits it entirely.
public struct WhatsNewHero: Equatable, Sendable, Codable {
    public let id: String
    public let badge: String?
    public let title: String
    public let body: String
    /// A bundled image asset name, resolved by whatever renders this, not a
    /// remote URL — the content ships inside the app binary.
    public let image: String?
    public let action: WhatsNewAction?

    public init(
        id: String,
        badge: String? = nil,
        title: String,
        body: String,
        image: String? = nil,
        action: WhatsNewAction? = nil,
    ) {
        self.id = id
        self.badge = badge
        self.title = title
        self.body = body
        self.image = image
        self.action = action
    }
}
