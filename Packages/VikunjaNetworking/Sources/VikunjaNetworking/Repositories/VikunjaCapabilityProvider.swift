import VikunjaCore

/// Hits `/api/v1/info` once and caches the result in memory for the session.
/// Features query `supports(_:)` instead of comparing versions by hand.
public actor VikunjaCapabilityProvider: CapabilityProvider {
    private static let minimumAPIV2Version = ServerVersion(major: 2, minor: 4, patch: 0)

    private let client: APIClient
    private var cachedInfo: VikunjaServerInfo?

    public init(client: APIClient) {
        self.client = client
    }

    public func serverInfo() async throws -> VikunjaServerInfo {
        if let cachedInfo {
            return cachedInfo
        }
        let info = try await fetchServerInfo()
        cachedInfo = info
        return info
    }

    /// Tries v1 first, the one endpoint guaranteed to exist on every server
    /// version this app has ever supported, including one too old for v2 at
    /// all. Falls back to v2's `/info` only on a 404 from v1's, which can
    /// only mean the server has removed `/api/v1/*` entirely (Vikunja's
    /// 4.0). v2's `/info` reports the same core fields v1's does (see
    /// `LocalAuthInfoDTO.registrationEnabled`'s doc comment for the one
    /// field that moved). Any other failure (network error, 500, ...)
    /// surfaces as-is rather than masking it behind a second,
    /// likely-also-failing request.
    private func fetchServerInfo() async throws -> VikunjaServerInfo {
        do {
            let dto: ServerInfoDTO = try await client.send(VikunjaEndpoints.info())
            return ServerInfoMapper.toDomain(dto)
        } catch VikunjaError.notFound {
            let dto: ServerInfoDTO = try await client.send(VikunjaEndpoints.infoV2())
            return ServerInfoMapper.toDomain(dto)
        }
    }

    public func supports(_ feature: VikunjaFeature) async -> Bool {
        guard let info = try? await serverInfo() else { return false }
        switch feature {
        case .caldav:
            return info.caldavEnabled
        case .totp:
            return info.totpEnabled
        case .registration:
            return info.registrationEnabled
        case .localAuth:
            return info.localAuthEnabled
        case .openIDConnect:
            return !info.oidcProviders.isEmpty
        case .apiV2:
            guard let version = ServerVersion(info.version) else { return false }
            return version >= Self.minimumAPIV2Version
        }
    }
}
