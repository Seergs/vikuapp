/// One smaller, non-headline feature listed below the hero (or on its own,
/// in a release with no hero at all).
public struct WhatsNewFeature: Equatable, Sendable, Codable {
    public let id: String
    /// An SF Symbol name, not a design-system token — this content is
    /// authored data, not a view, and picks its own icon per release.
    public let icon: String
    /// A `VikuColor` tint token name, resolved by whatever renders this.
    public let tint: String
    public let title: String
    public let body: String
    public let action: WhatsNewAction?

    public init(
        id: String,
        icon: String,
        tint: String,
        title: String,
        body: String,
        action: WhatsNewAction? = nil,
    ) {
        self.id = id
        self.icon = icon
        self.tint = tint
        self.title = title
        self.body = body
        self.action = action
    }
}
