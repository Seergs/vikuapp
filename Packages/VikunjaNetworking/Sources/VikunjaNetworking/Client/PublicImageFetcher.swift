import Foundation

/// Downloads a public image linked from a task description or comment (an
/// `<img>` that isn't an attachment of the user's instance).
///
/// It runs on its own session with no cookies, no credential storage and no
/// `Authorization` header, so a third-party host never sees anything that
/// identifies the account. Only `https` URLs reach it (see
/// `InlineImageSource.resolve`), and App Transport Security blocks insecure
/// redirects.
public struct PublicImageFetcher: Sendable {
    public enum FetchError: Error, Equatable {
        case badStatus(Int)
        case notAnImage
        case tooLarge
    }

    /// Larger files aren't worth holding in memory for an inline picture.
    public static let maxBytes = 20 * 1024 * 1024

    private let session: URLSession

    public init(session: URLSession = PublicImageFetcher.defaultSession) {
        self.session = session
    }

    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    public func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw FetchError.badStatus(http.statusCode)
        }
        guard http.mimeType?.lowercased().hasPrefix("image/") == true else {
            throw FetchError.notAnImage
        }
        guard data.count <= Self.maxBytes else {
            throw FetchError.tooLarge
        }
        return data
    }
}
