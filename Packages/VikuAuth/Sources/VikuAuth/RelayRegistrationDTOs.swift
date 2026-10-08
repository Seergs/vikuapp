import Foundation

/// Mirrors `viku-apn-relay`'s `POST /v1/registrations` request body exactly
/// (see that repo's README): `apns_token` hex-encoded, `webhook_secret` the
/// string sent verbatim as the HMAC key — the same string later goes into
/// the Vikunja webhook's own `secret` field, so whichever encoding is chosen
/// here must match what `WebhookRepositoryProtocol` sends Vikunja with.
/// `account_key` is this app's `InstanceAccount.id` as a string — the
/// relay's registration identity, opaque to the relay itself.
struct RelayRegisterRequestDTO: Encodable {
    let apnsToken: String
    let webhookSecret: String
    let vikunjaUserID: Int
    let accountKey: String

    enum CodingKeys: String, CodingKey {
        case apnsToken = "apns_token"
        case webhookSecret = "webhook_secret"
        case vikunjaUserID = "vikunja_user_id"
        case accountKey = "account_key"
    }
}

/// Mirrors the relay's `200` response body. `managementToken` authenticates
/// the later `DELETE /v1/registrations/{id}` call and is shown only in this
/// response — never persisted anywhere but the Keychain.
struct RelayRegisterResponseDTO: Decodable {
    let id: String
    let webhookURL: URL
    let managementToken: String

    enum CodingKeys: String, CodingKey {
        case id
        case webhookURL = "webhook_url"
        case managementToken = "management_token"
    }
}
