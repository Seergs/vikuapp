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
        let enabled = defaults.bool(forKey: Self.defaultsKey)
        self.isEnabled = enabled
        // iOS persists the last badge independently of our preference. Apply
        // the disabled state even on launches that never load widget data.
        if !enabled {
            Task { await clearBadgeIfDisabled() }
        }
    }

    /// Turning it off clears the icon immediately rather than leaving the
    /// last count showing until the next background/launch refresh.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.defaultsKey)
        if !enabled {
            Task { await clearBadgeIfDisabled() }
        }
    }

    /// `state` is whatever `TodaySnapshotLoader.loadState()` just produced —
    /// overdue-plus-due-today (`TodayWidgetContent.pendingCount`) becomes the
    /// icon's number. Clears the badge when the preference is off. Otherwise,
    /// states without content (`.notConnected`/`.needsAuth`/`.unavailable`)
    /// preserve the previous count through transient failures.
    func updateBadge(from state: TodayWidgetState) async {
        guard isEnabled else {
            await clearBadgeIfDisabled()
            return
        }
        guard case let .content(content) = state else { return }
        await writeBadgeCount(content.pendingCount)
    }

    private func clearBadgeIfDisabled() async {
        // The preference may have changed since this task was scheduled.
        guard !isEnabled else { return }
        await writeBadgeCount(0, expectedEnabled: false)
    }

    private func writeBadgeCount(_ count: Int, expectedEnabled: Bool = true) async {
        guard isEnabled == expectedEnabled else { return }
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
