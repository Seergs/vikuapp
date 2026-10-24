import VikuAuth
import VikunjaCore

/// Composition-root `PushNotificationRegistering`: ties the UIKit-bound
/// `APNsPermissionCenter` to a `PushRegistrationProviding`. The only type
/// in the app target that knows both sides exist.
///
/// `enable()` has several independent, uncoordinated callers (the
/// Notifications screen's own load/toggle, the launch-time
/// `AppContainer.syncNotificationWebhooksForAllAccounts()`, account
/// teardown) that can legitimately overlap in time. An actor by itself
/// only protects this type's own state. It does nothing to stop two
/// concurrent calls from each independently hitting
/// `permissionCenter.requestDeviceToken()` (device-wide, one continuation
/// slot) and the relay's `POST /v1/registrations` (rate-limited per IP,
/// not per account) — so `enable()` coalesces concurrent calls for the same
/// account into one relay round trip, and chains every call, same account
/// or not, one after another rather than letting them fire concurrently.
actor PushNotificationCoordinator: PushNotificationRegistering {
    private let permissionCenter: APNsPermissionCenter
    private let registrationService: PushRegistrationProviding

    private var inFlightEnables: [InstanceAccount.ID: Task<PushRegistration?, Error>] = [:]
    private var lastEnable: Task<Void, Never>?

    init(
        permissionCenter: APNsPermissionCenter = .shared,
        registrationService: PushRegistrationProviding = RelayPushRegistrationService(),
    ) {
        self.permissionCenter = permissionCenter
        self.registrationService = registrationService
    }

    func enable(vikunjaUserID: Int, accountID: InstanceAccount.ID) async throws -> PushRegistration? {
        if let existing = inFlightEnables[accountID] {
            return try await existing.value
        }

        let predecessor = lastEnable
        let task = Task<PushRegistration?, Error> { [permissionCenter, registrationService] in
            await predecessor?.value
            guard await permissionCenter.requestAuthorization() else { return nil }
            let deviceToken = try await permissionCenter.requestDeviceToken()
            return try await registrationService.register(
                deviceToken: deviceToken,
                vikunjaUserID: vikunjaUserID,
                accountID: accountID,
            )
        }
        inFlightEnables[accountID] = task
        lastEnable = Task { _ = try? await task.value }
        defer { inFlightEnables[accountID] = nil }

        return try await task.value
    }

    func disable(accountID: InstanceAccount.ID) async throws {
        try await registrationService.unregister(accountID: accountID)
    }

    func updatePreferences(groupOverdueNotifications: Bool, accountID: InstanceAccount.ID) async throws {
        try await registrationService.updatePreferences(
            groupOverdueNotifications: groupOverdueNotifications,
            accountID: accountID,
        )
    }
}
