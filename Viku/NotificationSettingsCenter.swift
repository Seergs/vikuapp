import Foundation
import Observation
import VikunjaCore

/// Owns the user's notification preferences. Reads from `UserDefaults` on
/// launch (a plain preference, not a credential — the HMAC secret and relay
/// registration live in the Keychain instead, via `RelayPushRegistrationService`)
/// and persists every change. One instance lives for the whole app, created
/// by the composition root and handed to `Settings` as `NotificationSettingsStore`.
@Observable
@MainActor
final class NotificationSettingsCenter: NotificationSettingsStore {
    private static let key = "notificationSettings"

    private(set) var settings: NotificationSettings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = NotificationSettings()
        }
    }

    func save(_ settings: NotificationSettings) {
        self.settings = settings
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
