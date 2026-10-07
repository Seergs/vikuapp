import Foundation

/// What `RelayPushRegistrationService` keeps in the Keychain between calls —
/// everything needed to resend an idempotent registration (`webhookSecret`,
/// so it doesn't churn on every call and force Vikunja webhooks to be
/// recreated) and to unregister later (`id` + `managementToken`).
struct PushRegistrationRecord: Codable, Equatable {
    let id: String
    let webhookSecret: String
    let webhookURL: URL
    let managementToken: String
    let apnsTokenHex: String
}
