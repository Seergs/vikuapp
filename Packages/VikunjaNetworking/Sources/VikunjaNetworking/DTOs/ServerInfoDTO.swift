/// Mirror of `GET /api/v1/info`. Vikunja exposes the feature flags enabled on this
/// instance here — it's the basis for `CapabilityProvider`.
struct ServerInfoDTO: Codable {
    let version: String
    let caldavEnabled: Bool?
    let totpEnabled: Bool?
    let registrationEnabled: Bool?
    /// The instance's upload cap as a human-readable string (e.g. `"20MB"`) —
    /// `MaxFileSizeParser` turns it into a byte count. Absent on older
    /// servers.
    let maxFileSize: String?
    /// Which login methods are enabled. Absent entirely on servers old
    /// enough to predate this field — see `AuthInfoDTO`.
    let auth: AuthInfoDTO?

    enum CodingKeys: String, CodingKey {
        case version
        case caldavEnabled = "caldav_enabled"
        case totpEnabled = "totp_enabled"
        case registrationEnabled = "registration_enabled"
        case maxFileSize = "max_file_size"
        case auth
    }
}

struct AuthInfoDTO: Codable {
    let local: LocalAuthInfoDTO?
    let openidConnect: OpenIDAuthInfoDTO?

    enum CodingKeys: String, CodingKey {
        case local
        case openidConnect = "openid_connect"
    }
}

struct LocalAuthInfoDTO: Codable {
    let enabled: Bool?
    /// Only where v2's `/info` puts registration status (v1 reports it at
    /// the top level instead, `ServerInfoDTO.registrationEnabled`).
    /// Verified against a real instance's `/api/v2/openapi.json`
    /// (`LocalAuthInfo`): the one field that actually moved between v1 and
    /// v2's otherwise-identical `/info` shape.
    let registrationEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled
        case registrationEnabled = "registration_enabled"
    }
}

struct OpenIDAuthInfoDTO: Codable {
    let enabled: Bool?
    let providers: [OIDCProviderDTO]?
}

/// One entry of `auth.openid_connect.providers`, mirroring Vikunja's Go
/// `openid.Provider` struct (`code.vikunja.io/api/pkg/modules/auth/openid`).
struct OIDCProviderDTO: Codable {
    let name: String?
    let key: String?
    let authURL: String?
    let clientID: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case name
        case key
        case authURL = "auth_url"
        case clientID = "client_id"
        case scope
    }
}
