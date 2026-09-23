import Foundation
import VikunjaCore

enum ServerInfoMapper {
    static func toDomain(_ dto: ServerInfoDTO) -> VikunjaServerInfo {
        VikunjaServerInfo(
            version: dto.version,
            caldavEnabled: dto.caldavEnabled ?? false,
            totpEnabled: dto.totpEnabled ?? false,
            // v1 reports this at the top level; v2 moved it under
            // `auth.local` (see `LocalAuthInfoDTO.registrationEnabled`'s doc
            // comment). Try both rather than assuming which shape sent it.
            registrationEnabled: dto.registrationEnabled ?? dto.auth?.local?.registrationEnabled ?? false,
            maxFileSizeBytes: MaxFileSizeParser.bytes(from: dto.maxFileSize),
            localAuthEnabled: dto.auth?.local?.enabled ?? true,
            oidcProviders: oidcProviders(from: dto.auth?.openidConnect),
        )
    }

    /// Drops a provider entry missing a field this client needs to build an
    /// authorization request, rather than failing the whole `/info` parse
    /// over one malformed provider.
    private static func oidcProviders(from dto: OpenIDAuthInfoDTO?) -> [OIDCProvider] {
        guard dto?.enabled == true else { return [] }
        return (dto?.providers ?? []).compactMap { provider in
            guard let key = provider.key,
                  let name = provider.name,
                  let authURLString = provider.authURL,
                  let authURL = URL(string: authURLString),
                  let clientID = provider.clientID
            else { return nil }
            return OIDCProvider(
                key: key,
                name: name,
                authURL: authURL,
                clientID: clientID,
                scope: provider.scope ?? "openid email profile",
            )
        }
    }
}
