import Foundation
import Testing
@testable import VikuUI

struct BundledMarkdownLoaderTests {
    private func loader() throws -> BundledMarkdownLoader {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Documentation.bundle")
        return try BundledMarkdownLoader(bundle: #require(Bundle(url: url)))
    }

    @Test
    func `loads English Markdown without changing formatting`() throws {
        let markdown = try loader().load(resource: "guide", preferredLanguages: ["en-US"])
        #expect(markdown == "## Guide\n\nUse **labels**.\n")
    }

    @Test(arguments: ["es-MX", "es_MX"])
    func `selects Spanish for a regional language preference`(language: String) throws {
        let markdown = try loader().load(resource: "guide", preferredLanguages: [language, "en"])
        #expect(markdown == "## Guía\n\nUsa **etiquetas**.\n")
    }

    @Test
    func `falls back to English for unsupported languages`() throws {
        let markdown = try loader().load(resource: "guide", preferredLanguages: ["fr-FR"])
        #expect(markdown.contains("## Guide"))
    }

    @Test
    func `falls back to English when a translation is missing`() throws {
        let markdown = try loader().load(resource: "english-only", preferredLanguages: ["es"])
        #expect(markdown.contains("English only"))
    }

    @Test
    func `missing articles report an error`() throws {
        let loader = try loader()
        #expect(throws: BundledMarkdownLoader.LoadError.missingResource) {
            try loader.load(resource: "missing", preferredLanguages: ["en"])
        }
    }

    @Test
    func `empty documents report an error`() throws {
        let loader = try loader()
        #expect(throws: BundledMarkdownLoader.LoadError.emptyDocument) {
            try loader.load(resource: "empty", preferredLanguages: ["en"])
        }
    }

    @Test(arguments: ["../guide", "en/guide", "en\\guide", ""])
    func `resource names cannot be paths`(resource: String) throws {
        let loader = try loader()
        #expect(throws: BundledMarkdownLoader.LoadError.missingResource) {
            try loader.load(resource: resource, preferredLanguages: ["en"])
        }
    }
}
