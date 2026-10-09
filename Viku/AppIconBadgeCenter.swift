import Foundation
import Observation
import UserNotifications
import VikunjaCore
import VikuWidgetKit

/// Owns the user's app-icon-badge preference (a plain `UserDefaults` flag,
/// not a credential) and is the only place that actually calls
/// `UNUserNotificationCenter.setBadgeCount(_:)` — `AppContainer` calls
/// `updateBadge(from:)` with the `TodayWidgetState` it already fetched for
/// the Today widget (see `refreshWidgetSnapshots()`), so turning the icon
/// badge on never costs a second network round trip. One instance lives for
/// the whole app, created by the composition root.
@Observable
@MainActor
final class AppIconBadgeCenter: AppIconBadgeStoring {
    private static let defaultsKey = "appIconBadgeEnabled"

    private(set) var isEnabled: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
    }

    /// Turning it off clears the icon immediately rather than leaving the
    /// last count showing until the next background/launch refresh.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.defaultsKey)
        if !enabled {
            Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
        }
    }

    /// `state` is whatever `TodaySnapshotLoader.loadState()` just produced —
    /// overdue-plus-due-today (`TodayWidgetContent.pendingCount`) becomes the
    /// icon's number. A no-op when the preference is off, or when there's no
    /// fresh content to show (`.notConnected`/`.needsAuth`/`.unavailable`
    /// leave whatever count was already showing in place, rather than
    /// clearing it on a merely transient failure).
    func updateBadge(from state: TodayWidgetState) async {
        guard isEnabled else { return }
        guard case let .content(content) = state else { return }
        try? await UNUserNotificationCenter.current().setBadgeCount(content.pendingCount)
    }
}
