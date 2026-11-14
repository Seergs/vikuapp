import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct QuickAddMagicContractTests {
    @Test(arguments: QuickAddMagicMode.allCases)
    func `all web modes map to the domain without losing frontend fields`(mode: QuickAddMagicMode) throws {
        let original = try fixture()
        let settings = try #require(original.settings).updatingQuickAddMagicMode(mode)
        let decoded = try JSONDecoder().decode(UserSettingsDTO.self, from: JSONEncoder().encode(settings))
        #expect(decoded.quickAddMagicMode == mode)
        #expect(decoded.frontendSettings == settings.frontendSettings)
    }

    @Test func `null or missing Magic uses the web default while disabled remains explicit`() throws {
        let dto = try fixture()
        #expect(dto.settings?.quickAddMagicMode == .todoist)
        let original = try #require(dto.settings)
        var settings = original
        settings.frontendSettings = nil
        #expect(settings.quickAddMagicMode == .vikunja)
        settings.frontendSettings = .null
        #expect(settings.quickAddMagicMode == .vikunja)
        settings.frontendSettings = .object(["color_schema": .string("auto")])
        #expect(settings.quickAddMagicMode == .vikunja)
        settings.frontendSettings = .object(["quick_add_magic_mode": .string("disabled")])
        #expect(settings.quickAddMagicMode == .disabled)
    }

    @Test func `unrecognized modes do not silently select another syntax or destroy malformed settings`() throws {
        var settings = try #require(fixture().settings)
        settings.frontendSettings = .object(["quick_add_magic_mode": .string("new-mode")])
        #expect(settings.quickAddMagicMode == nil)
        settings.frontendSettings = .array([.string("unexpected")])
        #expect(settings.quickAddMagicMode == nil)
        #expect(throws: VikunjaError.decoding("Expected frontend_settings object")) {
            try settings.updatingQuickAddMagicMode(.todoist)
        }
    }

    private func fixture() throws -> UserDTO {
        let url = try #require(Bundle.module.url(forResource: "user-quick-add-settings", withExtension: "json"))
        return try JSONDecoder().decode(UserDTO.self, from: Data(contentsOf: url))
    }
}
