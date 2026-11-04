import Foundation

protocol WhatsNewImageLoading: Sendable {
    func data(for url: URL) async throws -> Data
}

/// Public release artwork uses its own session, without Vikunja credentials.
/// Cache entries are disposable; publish a new URL when replacing artwork.
actor WhatsNewImageLoader: WhatsNewImageLoading {
    static let shared = WhatsNewImageLoader()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 20 * 1024 * 1024,
            diskPath: "whats-new-images",
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw URLError(.unsupportedURL)
        }
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              response.url?.scheme?.lowercased() == "https"
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
