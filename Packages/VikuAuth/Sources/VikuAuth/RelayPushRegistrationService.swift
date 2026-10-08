import CryptoKit
import Foundation
import VikunjaCore

/// Concrete `PushRegistrationProviding` talking to `viku-apn-relay` (see that
/// repo's README for the exact contract this mirrors). The HMAC secret is
/// generated on the device, once, and reused on every subsequent
/// `register(deviceToken:vikunjaUserID:accountID:)` call — the relay
/// replaces its stored secret on every call regardless, so resending the
/// same one keeps the Vikunja-side webhook valid instead of forcing it to be
/// recreated. The relay's `management_token` rotates on every call (the
/// previous one stops working immediately), so it's always overwritten.
public actor RelayPushRegistrationService: PushRegistrationProviding {
    public static let defaultBaseURL = URL(string: "https://relay.viku.dev")!

    private let baseURL: URL
    private let session: URLSession
    private let keychainService: String

    public init(
        baseURL: URL = RelayPushRegistrationService.defaultBaseURL,
        session: URLSession = .shared,
        keychainService: String = "dev.sergiosuarez.viku.push",
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychainService = keychainService
    }

    public func register(deviceToken: Data, vikunjaUserID: Int, accountID: InstanceAccount.ID) async throws -> PushRegistration {
        let apnsTokenHex = deviceToken.hexEncoded
        let account = Self.keychainAccount(for: accountID)
        let secret = try loadRecord(account: account)?.webhookSecret ?? Self.generateSecret()

        let body = RelayRegisterRequestDTO(
            apnsToken: apnsTokenHex,
            webhookSecret: secret,
            vikunjaUserID: vikunjaUserID,
            accountKey: accountID.uuidString,
        )
        let (data, response) = try await send(path: "/v1/registrations", method: "POST", body: body)
        try Self.validate(response, acceptableStatusCodes: [200])

        let decoded: RelayRegisterResponseDTO
        do {
            decoded = try JSONDecoder().decode(RelayRegisterResponseDTO.self, from: data)
        } catch {
            throw PushRegistrationError.invalidResponse
        }

        try saveRecord(
            PushRegistrationRecord(
                id: decoded.id,
                webhookSecret: secret,
                webhookURL: decoded.webhookURL,
                managementToken: decoded.managementToken,
                apnsTokenHex: apnsTokenHex,
            ),
            account: account,
        )
        return PushRegistration(targetURL: decoded.webhookURL, secret: secret)
    }

    public func unregister(accountID: InstanceAccount.ID) async throws {
        let account = Self.keychainAccount(for: accountID)
        guard let record = try loadRecord(account: account) else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/registrations/\(record.id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(record.managementToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)

        // 401 means the row (and its token) is already gone — per the
        // relay's README, "a repeated call returns 401 ... the end state is
        // the same" — so that's treated as success here too.
        try Self.validate(response, acceptableStatusCodes: [204, 401])
        try deleteRecord(account: account)
    }

    // MARK: - HTTP

    private func send(path: String, method: String, body: some Encodable) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await session.data(for: request)
    }

    private static func validate(_ response: URLResponse, acceptableStatusCodes: Set<Int>) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PushRegistrationError.invalidResponse
        }
        guard !acceptableStatusCodes.contains(http.statusCode) else { return }

        switch http.statusCode {
        case 400:
            throw PushRegistrationError.invalidRequest
        case 429:
            throw PushRegistrationError.rateLimited
        default:
            throw PushRegistrationError.server(statusCode: http.statusCode)
        }
    }

    // MARK: - Secret

    /// 32 random bytes, base64-encoded to a 44-character string — within the
    /// relay's documented 32-to-256-byte range for `webhook_secret`, and the
    /// exact string later sent to Vikunja as the webhook's `secret`.
    private static func generateSecret() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    // MARK: - Keychain

    /// One Keychain item per account, not one fixed item for the whole
    /// device — otherwise registering a second account would overwrite the
    /// first one's stored secret/management token locally, on top of the
    /// relay-side collision that would cause.
    private static func keychainAccount(for accountID: InstanceAccount.ID) -> String {
        "registration.\(accountID.uuidString)"
    }

    private func loadRecord(account: String) throws -> PushRegistrationRecord? {
        guard let data = try Keychain.read(service: keychainService, account: account) else {
            return nil
        }
        return try? JSONDecoder().decode(PushRegistrationRecord.self, from: data)
    }

    private func saveRecord(_ record: PushRegistrationRecord, account: String) throws {
        let data = try JSONEncoder().encode(record)
        try Keychain.save(data, service: keychainService, account: account)
    }

    private func deleteRecord(account: String) throws {
        try Keychain.delete(service: keychainService, account: account)
    }
}

private extension Data {
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
