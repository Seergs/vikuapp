import VikuAuth
import VikunjaCore

/// Composition-root `PushNotificationRegistering`: ties the UIKit-bound
/// `APNsPermissionCenter` to a `PushRegistrationProviding`. The only type
/// in the app target that knows both sides exist.
final class PushNotificationCoordinator: PushNotificationRegistering {
    private let permissionCenter: APNsPermissionCenter
    private let registrationService: PushRegistrationProviding

    init(
        permissionCenter: APNsPermissionCenter = .shared,
        registrationService: PushRegistrationProviding = RelayPushRegistrationService(),
    ) {
        self.permissionCenter = permissionCenter
        self.registrationService = registrationService
    }

    func enable(vikunjaUserID: Int) async throws -> PushRegistration? {
        guard await permissionCenter.requestAuthorization() else { return nil }
        let deviceToken = try await permissionCenter.requestDeviceToken()
        return try await registrationService.register(deviceToken: deviceToken, vikunjaUserID: vikunjaUserID)
    }

    func disable() async throws {
        try await registrationService.unregister()
    }
}
