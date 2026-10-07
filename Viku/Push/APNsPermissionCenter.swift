import UIKit
import UserNotifications

/// Bridges UIKit's callback-based APNs registration flow into `async`.
/// `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`/
/// `application(_:didFailToRegisterForRemoteNotificationsWithError:)` forward
/// to the shared instance, which resumes whichever continuation
/// `requestDeviceToken()` is awaiting.
final class APNsPermissionCenter {
    static let shared = APNsPermissionCenter()

    enum DeviceTokenError: LocalizedError, Equatable {
        /// Neither delegate callback fired within `deviceTokenTimeout`.
        /// Seen on some Simulator runtimes/OS versions, which don't always
        /// synthesize a token the way a real device does within
        /// milliseconds — without this, the request hangs forever and a
        /// retry crashes with "leaked its continuation without resuming it".
        case timedOut

        var errorDescription: String? {
            switch self {
            case .timedOut:
                String(localized: "Couldn't reach Apple's push service. Try again.")
            }
        }
    }

    /// Generous on purpose: a slow network shouldn't look identical to
    /// "notifications are broken" from the user's side.
    private static let deviceTokenTimeout: Duration = .seconds(10)

    private var tokenContinuation: CheckedContinuation<Data, Error>?
    /// Identifies which `requestDeviceToken()` call `tokenContinuation`
    /// belongs to, so a stale timeout task from an earlier call that's
    /// already been resumed can never touch a newer, still-pending one.
    private var requestToken = 0

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
    /// awaits the device token via the app delegate callback, or throws
    /// `DeviceTokenError.timedOut` if neither callback fires in time.
    func requestDeviceToken() async throws -> Data {
        // A previous call that never got a callback would otherwise have
        // its continuation silently overwritten below, which crashes at
        // runtime — resume it first so it fails instead of leaking.
        failPendingRequest(with: CancellationError())

        requestToken += 1
        let thisToken = requestToken

        return try await withCheckedThrowingContinuation { continuation in
            tokenContinuation = continuation
            UIApplication.shared.registerForRemoteNotifications()
            Task {
                try? await Task.sleep(for: Self.deviceTokenTimeout)
                guard requestToken == thisToken else { return }
                failPendingRequest(with: DeviceTokenError.timedOut)
            }
        }
    }

    /// Forwarded from `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func didReceive(deviceToken: Data) {
        tokenContinuation?.resume(returning: deviceToken)
        tokenContinuation = nil
    }

    /// Forwarded from `AppDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    func didFailToRegister(with error: Error) {
        failPendingRequest(with: error)
    }

    /// No-op if nothing is pending — safe to call even after the real
    /// callback (or the timeout) already resumed and cleared it.
    private func failPendingRequest(with error: Error) {
        tokenContinuation?.resume(throwing: error)
        tokenContinuation = nil
    }
}
