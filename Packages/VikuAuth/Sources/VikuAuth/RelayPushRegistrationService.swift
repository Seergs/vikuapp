import CryptoKit
import Foundation
import VikunjaCore

/// Concrete `PushRegistrationProviding` talking to `viku-apn-relay`
/// (`https://relay.viku.dev`, see that repo's README for the exact contract
/// this mirrors). The HMAC secret is generated on the device, once, and
/// reused on every subsequent `register(deviceToken:vikunjaUserID:)` call —
/// the relay replaces its stored secret on every call regardless, so resending
/// the same one keeps the Vikunja-side webhook valid instead of forcing it to
/// be recreated. The relay's `management_token` rotates on every call
/// (the previous one stops working immediately), so it's always overwritten.
public actor RelayPushRegistrationService: PushRegistrationProviding {
    public static let defaultBaseURL = URL(string: "https://relay.viku.dev")!
    private static let keychainAccount = "registration"

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

    public func register(deviceToken: Data, vikunjaUserID: Int) async throws -> PushRegistration {
        let apnsTokenHex = deviceToken.hexEncoded
        let secret = try loadRecord()?.webhookSecret ?? Self.generateSecret()

        let body = RelayRegisterRequestDTO(apnsToken: apnsTokenHex, webhookSecret: secret, vikunjaUserID: vikunjaUserID)
        let (data, response) = try await send(path: "/v1/registrations", method: "POST", body: body)
        try Self.validate(response, acceptableStatusCodes: [200])

        let decoded: RelayRegisterResponseDTO
        do {
            decoded = try JSONDecoder().decode(RelayRegisterResponseDTO.self, from: data)
        } catch {
            throw PushRegistrationError.invalidResponse
        }

        try saveRecord(PushRegistrationRecord(
            id: decoded.id,
            webhookSecret: secret,
            webhookURL: decoded.webhookURL,
            managementToken: decoded.managementToken,
            apnsTokenHex: apnsTokenHex,
        ))
        return PushRegistration(targetURL: decoded.webhookURL, secret: secret)
    }

    public func unregister() async throws {
        guard let record = try loadRecord() else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/registrations/\(record.id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(record.managementToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)

        // 401 means the row (and its token) is already gone — per the
        // relay's README, "a repeated call returns 401 ... the end state is
        // the same" — so that's treated as success here too.
        try Self.validate(response, acceptableStatusCodes: [204, 401])
        try deleteRecord()
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

    private func loadRecord() throws -> PushRegistrationRecord? {
        guard let data = try Keychain.read(service: keychainService, account: Self.keychainAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(PushRegistrationRecord.self, from: data)
    }

    private func saveRecord(_ record: PushRegistrationRecord) throws {
        let data = try JSONEncoder().encode(record)
        try Keychain.save(data, service: keychainService, account: Self.keychainAccount)
    }

    private func deleteRecord() throws {
        try Keychain.delete(service: keychainService, account: Self.keychainAccount)
    }
}

private extension Data {
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
