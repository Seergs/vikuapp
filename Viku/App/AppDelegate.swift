import BackgroundTasks
import UIKit
import UserNotifications
import VikuNavigation
import VikunjaPersistence

/// Backs the Home Screen long-press quick action ("New Task", declared as
/// `UIApplicationShortcutItems` in `Info.plist`). SwiftUI's `App` has no
/// scene-lifecycle hook of its own for `UIApplicationShortcutItem`, so this
/// thin `UIApplicationDelegate` exists only to hand the scene off to
/// `SceneDelegate`, which routes the tap through the same
/// `DeepLinkRouter.shared` a `viku://quick-add` URL or the Siri shortcut uses.
/// Also the `UNUserNotificationCenterDelegate` for push, set on launch below.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set from `VikuApp.init()` right after the composition root is built --
    /// `AppDelegate` is instantiated separately by `@UIApplicationDelegateAdaptor`,
    /// so this is the only way `userNotificationCenter(_:didReceive:)` can
    /// reach it to act on a notification action button without opening the
    /// app.
    @MainActor static var container: AppContainer?

    /// Matches the `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
    static let backgroundSyncTaskIdentifier = "\(Bundle.main.bundleIdentifier ?? "").sync-projects"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerPushNotificationCategories()
        registerBackgroundSyncTask()
        return true
    }

    /// Registers the handler for the opportunistic, OS-scheduled background
    /// pull/drain of every saved account's projects — the least important of
    /// `SyncCoordinator`'s sync triggers, since iOS gives no frequency
    /// guarantee; this only reduces staleness between opens, never the
    /// primary sync mechanism. Must run before this method returns, per
    /// `BGTaskScheduler`'s own requirement.
    private func registerBackgroundSyncTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundSyncTaskIdentifier, using: nil) { task in
            let syncTask = Task {
                await Self.container?.syncCoordinator.syncAllAccounts()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { syncTask.cancel() }
            Self.scheduleNextBackgroundSync()
        }
        Self.scheduleNextBackgroundSync()
    }

    /// Submits the next refresh request — called once at launch and again
    /// every time the previous one actually runs, so there's always one
    /// outstanding.
    static func scheduleNextBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Forwards to `APNsPermissionCenter.shared`, which resumes whichever
    /// continuation `requestDeviceToken()` is awaiting — see
    /// `PushNotificationCoordinator.enable(vikunjaUserID:)`.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        APNsPermissionCenter.shared.didReceive(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        APNsPermissionCenter.shared.didFailToRegister(with: error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Without a delegate at all, iOS silently drops a push while the app is
    /// in the foreground — delivery still succeeds (the relay/APNs logs show
    /// it), the banner just never appears, which looks indistinguishable
    /// from a broken delivery.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Fires on a tap, a dismiss, or an action button, whether it
    /// cold-launches the app, resumes it from the background, or it's
    /// already in the foreground. A tap parks the parsed `DeepLink` on the
    /// same `DeepLinkRouter.shared` a `viku://` URL or the Home Screen quick
    /// action uses — `MainTabView` resolves it into a task once its shell
    /// (and the right account's repositories) exist. Any other
    /// `actionIdentifier` (e.g. "Snooze 1h", "Due Tomorrow" — see
    /// `PushNotificationActionIdentifier`) is handled directly here, through
    /// `container`, without ever opening the app. `@MainActor` here, not on
    /// the whole conformance, because only this method touches
    /// `DeepLinkRouter`/`container`; the compiler inserts the actor hop since
    /// `UNUserNotificationCenterDelegate` is an `@objc` protocol.
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        guard let link = DeepLink(pushUserInfo: response.notification.request.content.userInfo) else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            DeepLinkRouter.shared.open(link)
            completionHandler()
        case UNNotificationDismissActionIdentifier:
            completionHandler()
        default:
            guard case let .task(id, accountKey) = link else {
                completionHandler()
                return
            }
            let actionIdentifier = response.actionIdentifier
            Task {
                try? await Self.container?.performNotificationAction(
                    actionIdentifier,
                    taskID: id,
                    accountKey: accountKey,
                )
                completionHandler()
            }
        }
    }
}

/// Handles the quick action both when it cold-launches the app
/// (`scene(_:willConnectTo:options:)`) and when the app is already
/// running/backgrounded (`windowScene(_:performActionFor:completionHandler:)`).
@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Matches `UIApplicationShortcutItemType` in Info.plist, which expands
    /// `$(PRODUCT_BUNDLE_IDENTIFIER)` per build config (Debug/Release use
    /// different bundle ids — see `VikuWidgetConfig.bundleIDPrefix`).
    static let quickAddActionType = "\(Bundle.main.bundleIdentifier ?? "").quick-add"

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        handle(shortcutItem)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void,
    ) {
        completionHandler(handle(shortcutItem))
    }

    @discardableResult
    private func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == Self.quickAddActionType else { return false }
        DeepLinkRouter.shared.open(.quickAdd(projectID: nil))
        return true
    }
}
