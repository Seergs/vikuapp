import Foundation
import Testing
@testable import VikunjaCore

@Suite("BundledWhatsNewContentProvider")
struct BundledWhatsNewContentProviderTests {
    private let provider = BundledWhatsNewContentProvider(bundle: .module)

    @Test
    func `loads the English file for an English locale`() {
        let content = provider.content(for: Locale(identifier: "en"))
        #expect(content?.release.title == "What's New in Viku")
    }

    @Test
    func `loads the Spanish file for a Spanish locale`() {
        let content = provider.content(for: Locale(identifier: "es"))
        #expect(content?.release.title == "Novedades en Viku")
    }

    @Test
    func `falls back to English for a locale with no shipped translation`() {
        let content = provider.content(for: Locale(identifier: "fr"))
        #expect(content?.release.title == "What's New in Viku")
    }

    @Test
    func `a bundle with no matching file returns nil rather than crashing`() throws {
        let emptyBundle = try #require(Bundle(path: NSTemporaryDirectory()))
        let provider = BundledWhatsNewContentProvider(bundle: emptyBundle)
        #expect(provider.content(for: Locale(identifier: "en")) == nil)
    }

    @Test
    func `a file that fails to decode returns nil rather than crashing`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("{ not valid json".utf8).write(to: directory.appending(path: "whats-new_en.json"))
        let brokenBundle = try #require(Bundle(path: directory.path))
        let provider = BundledWhatsNewContentProvider(bundle: brokenBundle)
        #expect(provider.content(for: Locale(identifier: "en")) == nil)
    }
}
