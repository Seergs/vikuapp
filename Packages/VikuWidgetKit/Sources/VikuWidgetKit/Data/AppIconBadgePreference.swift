import Foundation

/// Only the badge preference is shared; credentials remain in the Keychain.
/// The app mirrors its existing preference here on launch and on every change.
public struct AppIconBadgePreference: Sendable {
    private let suiteName: String
    private static let key = "appIconBadgeEnabled"

    public init(suiteName: String = VikuWidgetConfig.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    public var isEnabled: Bool {
        UserDefaults(suiteName: suiteName)?.bool(forKey: Self.key) ?? false
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults(suiteName: suiteName)?.set(enabled, forKey: Self.key)
    }
}
