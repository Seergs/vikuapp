import Foundation
import Testing
@testable import VikunjaNetworking

struct ServerInfoDTOTests {
    @Test
    func `maps capability flags to domain`() throws {
        let url = try #require(Bundle.module.url(forResource: "server_info", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: data)

        let info = ServerInfoMapper.toDomain(dto)

        #expect(info.version == "0.24.6")
        #expect(info.caldavEnabled == true)
        #expect(info.totpEnabled == true)
        #expect(info.registrationEnabled == false)
        #expect(info.maxFileSizeBytes == 20 * 1024 * 1024)
        #expect(info.localAuthEnabled == true)
    }

    @Test
    func `reads registrationEnabled from auth local when the top level key is absent`() throws {
        // v2's /info shape — verified against a real instance's
        // /api/v2/openapi.json: registration_enabled moved under auth.local.
        let json = #"""
        {
          "version": "2.4.0",
          "caldav_enabled": true,
          "totp_enabled": true,
          "max_file_size": "20MB",
          "auth": { "local": { "enabled": true, "registration_enabled": true } }
        }
        """#
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(json.utf8))

        #expect(ServerInfoMapper.toDomain(dto).registrationEnabled == true)
    }

    @Test
    func `prefers the top level registrationEnabled when both are present`() throws {
        let json = #"""
        {
          "version": "0.24.6",
          "registration_enabled": true,
          "auth": { "local": { "enabled": true, "registration_enabled": false } }
        }
        """#
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(json.utf8))

        #expect(ServerInfoMapper.toDomain(dto).registrationEnabled == true)
    }

    @Test
    func `defaults localAuthEnabled to true when the auth key is absent`() throws {
        let url = try #require(Bundle.module.url(forResource: "server_info", withExtension: "json"))
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(contentsOf: url))

        #expect(ServerInfoMapper.toDomain(dto).localAuthEnabled == true)
    }

    @Test
    func `defaults oidcProviders to empty when the auth key is absent`() throws {
        let url = try #require(Bundle.module.url(forResource: "server_info", withExtension: "json"))
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(contentsOf: url))

        #expect(ServerInfoMapper.toDomain(dto).oidcProviders.isEmpty)
    }

    @Test
    func `reads localAuthEnabled from the auth key when present`() throws {
        let url = try #require(Bundle.module.url(forResource: "server_info_with_auth", withExtension: "json"))
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(contentsOf: url))

        #expect(ServerInfoMapper.toDomain(dto).localAuthEnabled == false)
    }

    @Test
    func `maps oidc providers when openid connect is enabled`() throws {
        let url = try #require(Bundle.module.url(forResource: "server_info_with_auth", withExtension: "json"))
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(contentsOf: url))

        let providers = ServerInfoMapper.toDomain(dto).oidcProviders

        #expect(providers.count == 1)
        #expect(providers.first?.key == "authentik")
        #expect(providers.first?.name == "Authentik")
        #expect(providers.first?.authURL == URL(string: "https://auth.example.com/application/o/authorize/"))
        #expect(providers.first?.clientID == "vikunja-client-id")
        #expect(providers.first?.scope == "openid email profile")
    }

    @Test
    func `ignores configured oidc providers when openid connect is disabled`() throws {
        let json = """
        {
          "version": "0.24.6",
          "auth": {
            "openid_connect": {
              "enabled": false,
              "providers": [
                { "name": "Authentik", "key": "authentik", "auth_url": "https://auth.example.com/o/authorize/", "client_id": "id" }
              ]
            }
          }
        }
        """
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(json.utf8))

        #expect(ServerInfoMapper.toDomain(dto).oidcProviders.isEmpty)
    }

    @Test
    func `drops an oidc provider missing a required field`() throws {
        let json = """
        {
          "version": "0.24.6",
          "auth": {
            "openid_connect": {
              "enabled": true,
              "providers": [
                { "name": "Authentik", "key": "authentik", "auth_url": "https://auth.example.com/o/authorize/", "client_id": "id" },
                { "name": "Missing Auth URL", "key": "broken", "client_id": "id" }
              ]
            }
          }
        }
        """
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(json.utf8))

        let providers = ServerInfoMapper.toDomain(dto).oidcProviders

        #expect(providers.count == 1)
        #expect(providers.first?.key == "authentik")
    }

    @Test
    func `defaults an oidc provider's scope when the server omits it`() throws {
        let json = """
        {
          "version": "0.24.6",
          "auth": {
            "openid_connect": {
              "enabled": true,
              "providers": [
                { "name": "Authentik", "key": "authentik", "auth_url": "https://auth.example.com/o/authorize/", "client_id": "id" }
              ]
            }
          }
        }
        """
        let dto = try JSONDecoder().decode(ServerInfoDTO.self, from: Data(json.utf8))

        #expect(ServerInfoMapper.toDomain(dto).oidcProviders.first?.scope == "openid email profile")
    }

    @Test(arguments: [
        ("20MB", 20 * 1024 * 1024),
        ("20 MB", 20 * 1024 * 1024),
        ("20mb", 20 * 1024 * 1024),
        ("1GB", 1024 * 1024 * 1024),
        ("500KB", 500 * 1024),
        ("20MiB", 20 * 1024 * 1024),
        ("1048576", 1_048_576),
    ])
    func `parses max file size strings`(input: String, expected: Int) {
        #expect(MaxFileSizeParser.bytes(from: input) == expected)
    }

    @Test(arguments: ["", "  ", "lots", "MB", "-5MB", "12PB"])
    func `returns nil for unparseable max file size`(input: String) {
        #expect(MaxFileSizeParser.bytes(from: input) == nil)
    }

    @Test
    func `returns nil when max file size is absent`() {
        #expect(MaxFileSizeParser.bytes(from: nil) == nil)
    }
}
