/// The release this "What's New" content describes.
///
/// `version` is the content's own identity, used to decide whether it's
/// already been shown — it's a short display label ("1.3"), not necessarily
/// the exact build's marketing version, and it only changes when this
/// content is deliberately replaced. A release that ships with no new
/// `WhatsNewContent` (a patch, or a minor the maintainer chose not to
/// announce) simply keeps shipping the previous release's untouched file,
/// so `version` stays the same and nothing reappears.
///
/// `minAppVersion` is the separate eligibility floor: the lowest running app
/// version allowed to present this content at all. Decoupling the two lets a
/// release ship dormant (`minAppVersion` set ahead of the current app
/// version) while still being fully authored and testable in Debug builds,
/// which ignore this floor.
public struct WhatsNewRelease: Equatable, Sendable, Codable {
    public let version: String
    public let date: String
    public let minAppVersion: String
    public let title: String
    public let subtitle: String

    public init(
        version: String,
        date: String,
        minAppVersion: String,
        title: String,
        subtitle: String,
    ) {
        self.version = version
        self.date = date
        self.minAppVersion = minAppVersion
        self.title = title
        self.subtitle = subtitle
    }
}
