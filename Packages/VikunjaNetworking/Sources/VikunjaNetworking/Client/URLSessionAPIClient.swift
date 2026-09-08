import Foundation
import os
import VikunjaCore

private let apiLogger = Logger(subsystem: "dev.sergiosuarez.vikunja", category: "networking")

/// Concrete `APIClient` implementation on top of `URLSession`. This is the only piece
/// of the project that knows Vikunja speaks HTTP/JSON — `baseURL` and the token are
/// resolved via closures so this client stays decoupled from any particular account
/// or instance.
public actor URLSessionAPIClient: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let authTokenProvider: @Sendable () async -> String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: @escaping @Sendable () async -> String? = { nil },
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        let data = try await sendRaw(endpoint)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw VikunjaError.decoding(String(describing: error))
        }
    }

    public func send(_ endpoint: Endpoint) async throws {
        _ = try await sendRaw(endpoint)
    }

    public func data(_ endpoint: Endpoint) async throws -> Data {
        try await sendRaw(endpoint)
    }

    public func sendWithResponse<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (Response, HTTPURLResponse) {
        let (data, response) = try await sendRawWithResponse(endpoint)
        do {
            return try (decoder.decode(Response.self, from: data), response)
        } catch {
            throw VikunjaError.decoding(String(describing: error))
        }
    }

    private func sendRaw(_ endpoint: Endpoint) async throws -> Data {
        try await sendRawWithResponse(endpoint).0
    }

    private func sendRawWithResponse(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        guard let url = makeURL(for: endpoint) else {
            throw VikunjaError.invalidInstanceURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue(endpoint.contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = await authTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in endpoint.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VikunjaError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VikunjaError.network("Received a non-HTTP response from the server")
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return (data, httpResponse)
        case 401:
            Self.logFailedResponse(data, statusCode: 401, endpoint: endpoint)
            throw VikunjaError.unauthorized
        case 404:
            throw VikunjaError.notFound
        case 412:
            throw VikunjaError.totpRequired
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logFailedResponse(data, statusCode: httpResponse.statusCode, endpoint: endpoint)
            throw VikunjaError.server(message: message, statusCode: httpResponse.statusCode)
        }
    }

    /// Logs a failed request for diagnostics (filter Console.app by subsystem
    /// `dev.sergiosuarez.vikunja`). The response body and the request path are
    /// treated as sensitive: Vikunja's error/validation bodies echo back
    /// submitted task content, and task-scoped paths embed task IDs, both of
    /// which count as PII under the project's logging rules. The body is
    /// therefore emitted only in DEBUG builds, and the path is always marked
    /// `.private` so OSLog redacts it off-device. Auth failures (401/403)
    /// never log a body at all, since those responses can carry account
    /// context. `VikunjaError` still surfaces a generic message to the user.
    private static func logFailedResponse(_ data: Data, statusCode: Int, endpoint: Endpoint) {
        let method = endpoint.method.rawValue
        #if DEBUG
        if statusCode != 401, statusCode != 403 {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body, \(data.count) bytes>"
            apiLogger.error("\(method, privacy: .public) \(endpoint.path, privacy: .private) → \(statusCode, privacy: .public): \(body, privacy: .private)")
            return
        }
        #endif
        apiLogger.error("\(method, privacy: .public) \(endpoint.path, privacy: .private) → \(statusCode, privacy: .public)")
    }

    private func makeURL(for endpoint: Endpoint) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false,
        )
        if !endpoint.queryItems.isEmpty {
            components?.queryItems = endpoint.queryItems
        }
        return components?.url
    }
}
