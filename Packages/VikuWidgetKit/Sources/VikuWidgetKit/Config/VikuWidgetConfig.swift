import Foundation

/// Shared identifiers the app target and the widget extension must agree on.
/// These must match the App Group and `keychain-access-group` entries in both
/// targets' entitlements, and `accountStoreService` must match the `service`
/// the app's `KeychainAccountStore` is constructed with.
///
/// Everything derived from `bundleIDPrefix` is split per build configuration so
/// a Debug ("dev") install and a Release install on the same device never share
/// storage. The Swift side switches on `#if DEBUG`; the entitlements / Info.plist
/// side reads the matching `VIKU_ID_PREFIX` / `VIKU_URL_SCHEME` build
/// settings (project level, `project.pbxproj`) via `$(...)` expansion. Keep the
/// two in sync: Debug ↔ `.dev`, Release ↔ prod.
public enum VikuWidgetConfig {
    // The app's bundle-identifier prefix, shared by the app target and the
    // widget extension. Mirrors `VIKU_ID_PREFIX` in `project.pbxproj`.
    #if DEBUG
    public static let bundleIDPrefix = "dev.sergiosuarez.viku.dev"
    #else
    public static let bundleIDPrefix = "dev.sergiosuarez.viku"
    #endif

    /// App Group container holding the shared offline database the widgets
    /// read as their fallback. Added to the App Groups capability of both
    /// targets as `group.$(VIKU_ID_PREFIX)`.
    public static let appGroupIdentifier = "group.\(bundleIDPrefix)"

    /// Fully-qualified shared keychain group holding the account index, the
    /// active-account pointer, and each account's bearer token. Listed as
    /// `$(AppIdentifierPrefix)$(VIKU_ID_PREFIX).shared` under Keychain
    /// Sharing in both targets' entitlements. Keychain Services requires the
    /// expanded group at runtime, so the prefix comes from the target's
    /// Info.plist (`VikuAppIdentifierPrefix`) rather than being hardcoded.
    public static let keychainAccessGroup = "\(appIdentifierPrefix)\(bundleIDPrefix).shared"

    /// Xcode expands `$(AppIdentifierPrefix)` into both targets' Info.plist.
    /// Empty in package unit tests, which never construct a shared keychain
    /// store.
    private static let appIdentifierPrefix =
        Bundle.main.object(forInfoDictionaryKey: "VikuAppIdentifierPrefix") as? String ?? ""

    /// Must match the `service:` passed to `KeychainAccountStore` in the app's
    /// `AppContainer` and in `VikuWidgetEnvironment`.
    public static let accountStoreService = "\(bundleIDPrefix).accounts"

    /// `kind` string tying `TodayWidget` to `WidgetCenter.reloadTimelines(ofKind:)`.
    public static let todayWidgetKind = "TodayWidget"

    /// `kind` string for the large month-grid calendar widget (`CalendarWidget`).
    public static let calendarWidgetKind = "CalendarWidget"

    /// `kind` string for the Control Center quick-add control (`QuickAddControl`).
    public static let quickAddControlKind = "QuickAddControl"

    /// `kind` string for the Lock Screen quick-add accessory widget (`QuickAddWidget`).
    public static let quickAddWidgetKind = "QuickAddWidget"

    // URL scheme the widget deep-links back into the app with
    // (`viku://today`, `viku://quick-add`). Registered under the app
    // target's URL Types as `$(VIKU_URL_SCHEME)`; split per build config so
    // a dev and a prod install don't both claim the same scheme.
    #if DEBUG
    public static let urlScheme = "viku-dev"
    #else
    public static let urlScheme = "viku"
    #endif

    /// How many task rows the snapshot carries — enough for `.systemLarge`,
    /// keeping the cached payload and the extension's memory footprint small.
    public static let taskLimit = 8

    /// How many of the current day's task rows the calendar widget lists under
    /// its month grid — the large family only has room for a few.
    public static let calendarTaskLimit = 4

    /// Minimum spacing between timeline refreshes. WidgetKit only grants a
    /// bounded number of refreshes per day, so this stays coarse.
    public static let refreshInterval: TimeInterval = 30 * 60
}
