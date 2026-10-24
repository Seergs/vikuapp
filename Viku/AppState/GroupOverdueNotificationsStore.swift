import Foundation
import VikunjaCore

/// On-device, device-wide preference for whether overdue-task push
/// notifications arrive as one combined push instead of one per task. A
/// plain preference, not a credential, so `UserDefaults` is the right home
/// — mirrors `WhatsNewSeenVersionStore`'s shape. Unlike
/// `NotificationSettingsCenter`, there's no per-account dictionary here: see
/// `GroupOverdueNotificationsStoring`'s doc comment for why.
final class GroupOverdueNotificationsStore: GroupOverdueNotificationsStoring {
    private static let key = "groupOverdueNotifications.isEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.key)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}
