/// What a ViewModel needs to read and change the user's notification
/// preferences, without knowing anything about where they're persisted.
/// Implemented by a `UserDefaults`-backed store in the app target (a plain
/// preference, not a credential, so `UserDefaults` is the right home — the
/// device's HMAC secret and relay registration are a different concern,
/// kept in the Keychain by `PushRegistrationProviding`'s implementation)
/// and injected via `AppContainer`.
@MainActor
public protocol NotificationSettingsStore: AnyObject {
    var settings: NotificationSettings { get }
    func save(_ settings: NotificationSettings)
}
