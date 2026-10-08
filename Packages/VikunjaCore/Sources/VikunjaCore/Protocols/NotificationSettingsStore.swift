/// What a ViewModel needs to read and change the user's notification
/// preferences, without knowing anything about where they're persisted.
/// Implemented by a `UserDefaults`-backed store in the app target (a plain
/// preference, not a credential, so `UserDefaults` is the right home — the
/// device's HMAC secret and relay registration are a different concern,
/// kept in the Keychain by `PushRegistrationProviding`'s implementation)
/// and injected via `AppContainer`.
///
/// Scoped per `InstanceAccount.ID`, not global: the app supports several
/// saved connections, and which projects/events are enabled is meaningful
/// only within one of them — project ids are only unique within a single
/// Vikunja instance.
@MainActor
public protocol NotificationSettingsStore: AnyObject {
    func settings(for accountID: InstanceAccount.ID) -> NotificationSettings
    func save(_ settings: NotificationSettings, for accountID: InstanceAccount.ID)
}
