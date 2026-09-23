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
        let dto: ServerInfoDTO = try await client.send(VikunjaEndpoints.info())
        let info = ServerInfoMapper.toDomain(dto)
        cachedInfo = info
        return info
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
