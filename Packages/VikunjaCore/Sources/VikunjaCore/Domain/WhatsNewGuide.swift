/// A step-by-step "how to" screen, opened from a hero or feature's
/// `.guide` action. Keyed by its own id in `WhatsNewContent.guides`, since a
/// release may define several (one per feature that needs one).
public struct WhatsNewGuide: Hashable, Sendable, Codable {
    public struct Step: Hashable, Sendable, Codable {
        public let title: String
        public let body: String
        /// A bundled image asset name; `nil` renders a placeholder rather
        /// than an empty gap.
        public let image: String?

        public init(title: String, body: String, image: String? = nil) {
            self.title = title
            self.body = body
            self.image = image
        }
    }

    public let title: String
    public let intro: String
    public let steps: [Step]
    public let tip: String?
    public let primaryAction: WhatsNewAction?
    public let secondaryAction: WhatsNewAction?

    public init(
        title: String,
        intro: String,
        steps: [Step],
        tip: String? = nil,
        primaryAction: WhatsNewAction? = nil,
        secondaryAction: WhatsNewAction? = nil,
    ) {
        self.title = title
        self.intro = intro
        self.steps = steps
        self.tip = tip
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}
