import Foundation
import Observation
import VikunjaCore

/// Owns the user's notification preferences, one `NotificationSettings` per
/// saved connection — a single global blob would let two accounts' project
/// selections collide. Reads from `UserDefaults` on launch (a plain
/// preference, not a credential — the HMAC secret and relay registration
/// live in the Keychain instead, via `RelayPushRegistrationService`) and
/// persists every change. One instance lives for the whole app, created by
/// the composition root and handed to `Settings` as `NotificationSettingsStore`.
@Observable
@MainActor
final class NotificationSettingsCenter: NotificationSettingsStore {
    private static let key = "notificationSettings"

    private var allSettings: [String: NotificationSettings]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: NotificationSettings].self, from: data) {
            self.allSettings = decoded
        } else {
            self.allSettings = [:]
        }
    }

    func settings(for accountID: InstanceAccount.ID) -> NotificationSettings {
        allSettings[accountID.uuidString] ?? NotificationSettings()
    }

    func save(_ settings: NotificationSettings, for accountID: InstanceAccount.ID) {
        allSettings[accountID.uuidString] = settings
        guard let data = try? JSONEncoder().encode(allSettings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
