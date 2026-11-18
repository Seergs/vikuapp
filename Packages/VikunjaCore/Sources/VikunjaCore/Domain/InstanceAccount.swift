import Foundation

/// A configured connection to a Vikunja instance. The credential (an API
/// token, or an opaque password-session blob when `authMethod == .password`)
/// is never stored here — it lives in the Keychain, referenced by `id`,
/// behind `AccountStoreProtocol`.
public struct InstanceAccount: Identifiable, Hashable, Sendable, Codable {
    /// Which login method produced this account's stored credential.
    public enum AuthMethod: String, Sendable, Codable {
        case apiToken
        case password
        case oidc
    }

    public let id: UUID
    public var displayName: String
    public var baseURL: URL
    public var createdAt: Date
    public var authMethod: AuthMethod
    /// Server-local identity. Older beta connections bind on their first successful user lookup.
    public var userID: Int?
    public var username: String?
    /// Set by `PasswordSessionRefresher` when a password/OIDC session's
    /// refresh token is itself rejected by the server — the stored
    /// credential can no longer be renewed, only replaced by signing in
    /// again. Cleared back to `false` the next time this account's
    /// credential is stored (`ConnectionEditorCore.storeAccount`), i.e. on a
    /// successful re-authentication. Always `false` for `.apiToken`
    /// accounts, which never refresh. Defaults to `false` when decoding an
    /// account saved before this field existed.
    public var needsReauthentication: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        baseURL: URL,
        createdAt: Date = Date(),
        authMethod: AuthMethod = .apiToken,
        needsReauthentication: Bool = false,
        userID: Int? = nil,
        username: String? = nil,
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.createdAt = createdAt
        self.authMethod = authMethod
        self.userID = userID
        self.username = username
        self.needsReauthentication = needsReauthentication
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case baseURL
        case createdAt
        case authMethod
        case needsReauthentication
        case userID
        case username
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.baseURL = try container.decode(URL.self, forKey: .baseURL)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.authMethod = try container.decode(AuthMethod.self, forKey: .authMethod)
        self.needsReauthentication = try container.decodeIfPresent(Bool.self, forKey: .needsReauthentication) ?? false
        self.userID = try container.decodeIfPresent(Int.self, forKey: .userID)
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
    }

    /// Metadata updates may establish a legacy identity, but never remove or change one.
    public func validateIdentity(of replacement: InstanceAccount) throws {
        guard id == replacement.id, baseURL == replacement.baseURL else {
            throw ConnectionIdentityError.serverChanged
        }
        if let userID, replacement.userID != userID {
            throw ConnectionIdentityError.userChanged
        }
        if let newID = replacement.userID, newID <= 0 {
            throw ConnectionIdentityError.unverifiedUser
        }
    }
}
