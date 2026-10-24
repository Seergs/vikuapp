import Foundation
import VikunjaCore

/// On-device record of the "What's New" `release.version` this device has
/// already shown. A plain preference, not a credential, so `UserDefaults`
/// is the right home. Mirrors `ServerVersionStore`'s shape.
struct WhatsNewSeenVersionStore: WhatsNewSeenVersionStoring {
    private static let key = "whatsNew.lastSeenReleaseVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSeenReleaseVersion: String? {
        defaults.string(forKey: Self.key)
    }

    func setLastSeenReleaseVersion(_ version: String?) {
        if let version {
            defaults.set(version, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
