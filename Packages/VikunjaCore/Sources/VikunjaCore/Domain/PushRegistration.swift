import Foundation

/// What the relay (`viku-apn-relay`, a separate repo) hands back when this
/// device registers: where its Vikunja webhooks should point, and the HMAC
/// secret those webhooks are created with. The relay assigns the opaque
/// device id that's embedded in `targetURL`, so nothing here identifies the
/// device directly — `targetURL` itself is already the unique handle
/// `WebhookSyncing` uses to recognize "a webhook this device created"
/// among whatever else a user's Vikunja instance has configured.
public struct PushRegistration: Equatable, Sendable {
    public let targetURL: URL
    public let secret: String

    public init(targetURL: URL, secret: String) {
        self.targetURL = targetURL
        self.secret = secret
    }
}
