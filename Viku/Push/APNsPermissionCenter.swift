import UIKit
import UserNotifications

/// Bridges UIKit's callback-based APNs registration flow into `async`.
/// `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`/
/// `application(_:didFailToRegisterForRemoteNotificationsWithError:)` forward
/// to the shared instance, which resumes whichever continuation
/// `requestDeviceToken()` is awaiting.
final class APNsPermissionCenter {
    static let shared = APNsPermissionCenter()

    private var tokenContinuation: CheckedContinuation<Data, Error>?

    private init() {}

    /// Requests OS notification authorization. `false` means denied (or
    /// previously denied) — the caller must not go on to
    /// `requestDeviceToken()`, since `UIApplication.registerForRemoteNotifications()`
    /// would just fail silently.
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Calls `UIApplication.shared.registerForRemoteNotifications()` and
    /// awaits the device token via the app delegate callback. Only one
    /// registration can be in flight at a time; a second call while the
    /// first is still pending replaces its continuation, which then never
    /// resumes — callers are expected to await one at a time, matching how
    /// `PushNotificationCoordinator` uses this.
    func requestDeviceToken() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            tokenContinuation = continuation
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didReceive(deviceToken: Data) {
        tokenContinuation?.resume(returning: deviceToken)
        tokenContinuation = nil
    }

    func didFailToRegister(with error: Error) {
        tokenContinuation?.resume(throwing: error)
        tokenContinuation = nil
    }
}
