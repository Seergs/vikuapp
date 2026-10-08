import Foundation
import Testing
@testable import VikuAuth
import VikunjaCore

/// Exercises the real Keychain (see `KeychainAccountStoreTests`), so this
/// suite runs serialized against a service namespace unique to the test
/// process to avoid clobbering state across parallel test runs.
@Suite(.serialized)
struct RelayPushRegistrationServiceTests {
    private static let accountA = UUID()
    private static let accountB = UUID()

    private func makeService(session: URLSession) -> RelayPushRegistrationService {
        RelayPushRegistrationService(
            baseURL: URL(string: "https://relay.example.com")!,
            session: session,
            keychainService: "dev.sergiosuarez.viku.tests.push.\(UUID().uuidString)",
        )
    }

    private static let registerResponse = """
    {"id": "reg-1", "webhook_url": "https://relay.example.com/h/reg-1", "management_token": "mgmt-token-1"}
    """

    // MARK: register

    @Test
    func `register posts the hex encoded token and a generated secret, then returns the relay's webhook url`() async throws {
        let session = MockURLProtocol.makeSession(responses: [(200, Self.registerResponse)])
        let service = makeService(session: session)

        let registration = try await service.register(
            deviceToken: Data([0xAB, 0xCD]),
            vikunjaUserID: 42,
            accountID: Self.accountA,
        )

        #expect(registration.targetURL == URL(string: "https://relay.example.com/h/reg-1"))
        #expect(!registration.secret.isEmpty)

        let request = try #require(MockURLProtocol.capturedRequests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/registrations")
        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(CapturedRegisterBody.self, from: body)
        #expect(decoded.apnsToken == "abcd")
        #expect(decoded.webhookSecret == registration.secret)
        #expect(decoded.vikunjaUserID == 42)
        #expect(decoded.accountKey == Self.accountA.uuidString)
    }

    @Test
    func `registering again for the same account reuses the same secret instead of generating a new one`() async throws {
        let session = MockURLProtocol.makeSession(
            responses: [(200, Self.registerResponse), (200, Self.registerResponse)],
        )
        let service = makeService(session: session)

        let first = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        let second = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)

        #expect(first.secret == second.secret)
    }

    @Test
    func `registering a second account on the same device token keeps a separate secret`() async throws {
        let session = MockURLProtocol.makeSession(
            responses: [(200, Self.registerResponse), (200, Self.registerResponse)],
        )
        let service = makeService(session: session)

        let accountA = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        let accountB = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 7, accountID: Self.accountB)

        #expect(accountA.secret != accountB.secret)

        let bodies = try MockURLProtocol.capturedRequests.map {
            try JSONDecoder().decode(CapturedRegisterBody.self, from: #require($0.httpBody))
        }
        #expect(bodies.map(\.accountKey) == [Self.accountA.uuidString, Self.accountB.uuidString])
    }

    @Test
    func `a 429 response surfaces as rateLimited`() async throws {
        let session = MockURLProtocol.makeSession(responses: [(429, "")])
        let service = makeService(session: session)

        await #expect(throws: PushRegistrationError.rateLimited) {
            try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        }
    }

    @Test
    func `a 400 response surfaces as invalidRequest`() async throws {
        let session = MockURLProtocol.makeSession(responses: [(400, "")])
        let service = makeService(session: session)

        await #expect(throws: PushRegistrationError.invalidRequest) {
            try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        }
    }

    @Test
    func `an unparseable success body surfaces as invalidResponse`() async throws {
        let session = MockURLProtocol.makeSession(responses: [(200, "not json")])
        let service = makeService(session: session)

        await #expect(throws: PushRegistrationError.invalidResponse) {
            try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        }
    }

    // MARK: unregister

    @Test
    func `unregister sends the management token as a bearer header against the registration id`() async throws {
        let session = MockURLProtocol.makeSession(responses: [(200, Self.registerResponse), (204, "")])
        let service = makeService(session: session)
        _ = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)

        try await service.unregister(accountID: Self.accountA)

        let request = try #require(MockURLProtocol.capturedRequests.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/registrations/reg-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mgmt-token-1")
    }

    @Test
    func `unregister with nothing registered is a no op`() async throws {
        let session = MockURLProtocol.makeSession(responses: [])
        let service = makeService(session: session)

        try await service.unregister(accountID: Self.accountA)

        #expect(MockURLProtocol.capturedRequests.isEmpty)
    }

    @Test
    func `unregister treats a 401 as already gone rather than an error`() async throws {
        let session = MockURLProtocol.makeSession(responses: [(200, Self.registerResponse), (401, "")])
        let service = makeService(session: session)
        _ = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)

        try await service.unregister(accountID: Self.accountA)

        // The record is gone, so a second unregister has nothing to send.
        try await service.unregister(accountID: Self.accountA)
        #expect(MockURLProtocol.capturedRequests.count == 2)
    }

    @Test
    func `unregistering one account leaves another account's registration on the same device untouched`() async throws {
        let session = MockURLProtocol.makeSession(
            responses: [(200, Self.registerResponse), (200, Self.registerResponse), (204, "")],
        )
        let service = makeService(session: session)
        _ = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        _ = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 7, accountID: Self.accountB)

        try await service.unregister(accountID: Self.accountA)

        // Unregistering A must not have sent anything for B, and B's record
        // must still be there for a later unregister to use.
        #expect(MockURLProtocol.capturedRequests.count == 3)
    }

    @Test
    func `registering again after an unregister generates a fresh secret`() async throws {
        let session = MockURLProtocol.makeSession(
            responses: [(200, Self.registerResponse), (204, ""), (200, Self.registerResponse)],
        )
        let service = makeService(session: session)
        let first = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)
        try await service.unregister(accountID: Self.accountA)

        let second = try await service.register(deviceToken: Data([0x01]), vikunjaUserID: 1, accountID: Self.accountA)

        #expect(first.secret != second.secret)
    }
}

private struct CapturedRegisterBody: Decodable {
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
