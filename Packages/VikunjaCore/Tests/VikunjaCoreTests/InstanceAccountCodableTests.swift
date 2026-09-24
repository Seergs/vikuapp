import Foundation
import Testing
@testable import VikunjaCore

@Suite("InstanceAccount Codable")
struct InstanceAccountCodableTests {
    @Test
    func `round-trips a password account through encode/decode`() throws {
        let account = try InstanceAccount(
            displayName: "Home",
            baseURL: #require(URL(string: "https://tasks.example.com")),
            authMethod: .password,
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstanceAccount.self, from: encoder.encode(account))
        #expect(decoded == account)
        #expect(decoded.authMethod == .password)
    }

    @Test
    func `round-trips a flagged needsReauthentication account`() throws {
        let account = try InstanceAccount(
            displayName: "Home",
            baseURL: #require(URL(string: "https://tasks.example.com")),
            authMethod: .oidc,
            needsReauthentication: true,
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstanceAccount.self, from: encoder.encode(account))
        #expect(decoded.needsReauthentication)
    }

    @Test
    func `decoding an account saved before needsReauthentication existed defaults it to false`() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "displayName": "Home",
            "baseURL": "https://tasks.example.com",
            "createdAt": 0,
            "authMethod": "apiToken"
        }
        """
        let decoded = try JSONDecoder().decode(InstanceAccount.self, from: Data(json.utf8))
        #expect(decoded.needsReauthentication == false)
    }
}
