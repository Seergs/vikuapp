/// What `DefaultProjectSettingsViewModel` needs in order to show the
/// account's last known IANA time zone (`User.timezone`) immediately, before
/// its own `load()` resolves, without knowing anything about `UserDefaults`
/// or account ids. Implemented by `AccountTimezoneCache` in the app target,
/// scoped to one account, and injected via `AppContainer` the same way
/// `DefaultProjectCaching` is.
@MainActor
public protocol AccountTimezoneCaching {
    func cachedTimezone() -> String?
    func setCachedTimezone(_ timezone: String?)
}
