import Foundation
import Testing
@testable import VikuUI

struct MarkdownFrontMatterTests {
    @Test
    func `parses fields and returns the body untouched`() {
        let parsed = MarkdownFrontMatter(parsing: "---\ntitle: Offline\nicon: wifi.slash\n---\n# Heading\n\nBody  \n")
        #expect(parsed.fields == ["title": "Offline", "icon": "wifi.slash"])
        #expect(parsed["title"] == "Offline")
        #expect(parsed.body == "# Heading\n\nBody  \n")
    }

    @Test(arguments: ["# Title\n\nText\n", "", "Intro\n---\ntitle: x\n---\n", "---\n\nUnclosed\n"])
    func `documents without front matter pass through`(text: String) {
        let parsed = MarkdownFrontMatter(parsing: text)
        #expect(parsed.fields.isEmpty)
        #expect(parsed.body == text)
    }

    @Test
    func `later thematic breaks stay in the body`() {
        let parsed = MarkdownFrontMatter(parsing: "---\ntitle: A\n---\nOne\n\n---\n\nTwo\n")
        #expect(parsed.body == "One\n\n---\n\nTwo\n")
    }

    @Test
    func `values split at the first colon and are trimmed`() {
        let parsed = MarkdownFrontMatter(parsing: "---\ntitle:   Setup: step one  \nempty:\nno colon here\n---\n")
        #expect(parsed.fields == ["title": "Setup: step one", "empty": ""])
    }

    @Test
    func `handles an empty body and CRLF line endings`() {
        #expect(MarkdownFrontMatter(parsing: "---\ntitle: A\n---").body.isEmpty)

        let crlf = MarkdownFrontMatter(parsing: "---\r\ntitle: A\r\n---\r\nBody\r\n")
        #expect(crlf["title"] == "A")
        #expect(crlf.body == "Body\r\n")
    }

    @Test
    func `reads ISO dates as the written UTC day`() throws {
        let parsed = MarkdownFrontMatter(parsing: "---\nupdated: 2026-10-23\nbad: 23/10/2026\n---\n")
        let date = try #require(parsed.date(for: "updated"))
        let style = Date.FormatStyle(timeZone: .gmt).year().month().day().locale(Locale(identifier: "en_US"))
        #expect(date.formatted(style) == "Oct 23, 2026")
        #expect(parsed.date(for: "bad") == nil)
        #expect(parsed.date(for: "missing") == nil)
    }

    @Test
    func `reads comma separated lists`() {
        let parsed = MarkdownFrontMatter(parsing: "---\nrelated:  a, b ,, c\nnone:\n---\n")
        #expect(parsed.list(for: "related") == ["a", "b", "c"])
        #expect(parsed.list(for: "none").isEmpty)
        #expect(parsed.list(for: "missing").isEmpty)
    }
}
