import UIKit
import VikuNavigation

/// Backs the Home Screen long-press quick action ("New Task", declared as
/// `UIApplicationShortcutItems` in `Info.plist`). SwiftUI's `App` has no
/// scene-lifecycle hook of its own for `UIApplicationShortcutItem`, so this
/// thin `UIApplicationDelegate` exists only to hand the scene off to
/// `SceneDelegate`, which routes the tap through the same
/// `DeepLinkRouter.shared` a `viku://quick-add` URL or the Siri shortcut uses.
final class AppDelegate: NSObject, UIApplicationDelegate {
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
