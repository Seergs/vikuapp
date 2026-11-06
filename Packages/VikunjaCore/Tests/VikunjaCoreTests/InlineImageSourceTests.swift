import Foundation
import Testing
@testable import VikunjaCore

@Suite("InlineImageSource.resolve")
struct InlineImageSourceTests {
    private static let instance = URL(string: "https://vikunja.example.com")!

    private func resolve(_ source: String, instance: URL = Self.instance) -> InlineImageSource? {
        InlineImageSource.resolve(source, instanceURL: instance)
    }

    @Test
    func `recognizes an attachment the web editor stored in data-src`() {
        let source = "https://vikunja.example.com/api/v1/tasks/284/attachments/8"
        #expect(resolve(source) == .attachment(taskID: 284, attachmentID: 8))
    }

    @Test
    func `accepts the v2 and the unversioned attachment path`() {
        #expect(resolve("https://vikunja.example.com/api/v2/tasks/1/attachments/2") == .attachment(taskID: 1, attachmentID: 2))
        #expect(resolve("https://vikunja.example.com/tasks/1/attachments/2") == .attachment(taskID: 1, attachmentID: 2))
    }

    @Test
    func `resolves a root-relative attachment path against the instance`() {
        #expect(resolve("/api/v1/tasks/5/attachments/9") == .attachment(taskID: 5, attachmentID: 9))
    }

    @Test
    func `matches an instance served from a subpath`() throws {
        let instance = try #require(URL(string: "https://example.com/vikunja/"))
        #expect(
            resolve("https://example.com/vikunja/api/v1/tasks/5/attachments/9", instance: instance)
                == .attachment(taskID: 5, attachmentID: 9),
        )
        #expect(resolve("https://example.com/api/v1/tasks/5/attachments/9", instance: instance) == nil)
    }

    @Test
    func `ignores a legacy api suffix and letter case in the instance URL`() throws {
        let instance = try #require(URL(string: "https://Vikunja.Example.com/api/v1/"))
        #expect(
            resolve("https://vikunja.example.com/api/v1/tasks/3/attachments/4", instance: instance)
                == .attachment(taskID: 3, attachmentID: 4),
        )
    }

    @Test
    func `rejects an attachment of another instance so the token never leaves`() {
        #expect(resolve("https://other.example.com/api/v1/tasks/284/attachments/8") == nil)
        #expect(resolve("https://vikunja.example.com:8443/api/v1/tasks/284/attachments/8") == nil)
        #expect(resolve("http://vikunja.example.com/api/v1/tasks/284/attachments/8") == nil)
    }

    @Test
    func `loads attachments from an instance the user allowed over http`() throws {
        let instance = try #require(URL(string: "http://192.168.1.10:3456"))
        #expect(
            resolve("http://192.168.1.10:3456/api/v1/tasks/1/attachments/1", instance: instance)
                == .attachment(taskID: 1, attachmentID: 1),
        )
    }

    @Test
    func `treats any other https image as remote`() throws {
        let source = "https://images.example.org/cat.png?size=large"
        #expect(try resolve(source) == .remote(#require(URL(string: source))))
    }

    @Test
    func `rejects insecure, placeholder, and malformed sources`() throws {
        #expect(resolve("http://images.example.org/cat.png") == nil)
        #expect(resolve("#") == nil)
        #expect(resolve("   ") == nil)
        #expect(resolve("cat.png") == nil)
        #expect(resolve("data:image/png;base64,AAAA") == nil)
        #expect(try resolve("https://vikunja.example.com/api/v1/tasks/abc/attachments/8") == .remote(
            #require(URL(string: "https://vikunja.example.com/api/v1/tasks/abc/attachments/8")),
        ))
    }
}
