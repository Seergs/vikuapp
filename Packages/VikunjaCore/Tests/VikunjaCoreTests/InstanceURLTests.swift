import Testing
@testable import VikunjaCore

struct InstanceURLTests {
    @Test
    func `accepts A bare domain and defaults to HTTPS`() throws {
        let url = try InstanceURL.normalize("tasks.example.com")

        #expect(url.absoluteString == "https://tasks.example.com")
    }

    @Test
    func `accepts A full HTTPSURL`() throws {
        let url = try InstanceURL.normalize("https://tasks.example.com")

        #expect(url.absoluteString == "https://tasks.example.com")
    }

    @Test
    func `rejects HTTP by default`() {
        #expect(throws: VikunjaError.insecureInstanceURL) {
            try InstanceURL.normalize("http://localhost:3456")
        }
    }

    @Test
    func `accepts HTTP when insecure connections are opted in`() throws {
        let url = try InstanceURL.normalize("http://localhost:3456", allowInsecureHTTP: true)

        #expect(url.absoluteString == "http://localhost:3456")
    }

    @Test
    func `still defaults A bare domain to HTTPS even when insecure is allowed`() throws {
        let url = try InstanceURL.normalize("tasks.example.com", allowInsecureHTTP: true)

        #expect(url.absoluteString == "https://tasks.example.com")
    }

    @Test
    func `trims surrounding whitespace`() throws {
        let url = try InstanceURL.normalize("  tasks.example.com  ")

        #expect(url.absoluteString == "https://tasks.example.com")
    }

    @Test
    func `strips A pasted path query and trailing slash`() throws {
        let url = try InstanceURL.normalize("https://tasks.example.com/login?next=/tasks")

        #expect(url.absoluteString == "https://tasks.example.com")
    }

    @Test
    func `rejects an empty string`() {
        #expect(throws: VikunjaError.invalidInstanceURL) {
            try InstanceURL.normalize("   ")
        }
    }

    @Test
    func `rejects an unsupported scheme`() {
        #expect(throws: VikunjaError.invalidInstanceURL) {
            try InstanceURL.normalize("ftp://tasks.example.com")
        }
    }

    @Test
    func `rejects garbage input`() {
        #expect(throws: VikunjaError.invalidInstanceURL) {
            try InstanceURL.normalize("not a url")
        }
    }
}
