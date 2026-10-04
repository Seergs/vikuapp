import Foundation

public struct Endpoint: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    public let path: String
    public let method: Method
    public let queryItems: [URLQueryItem]
    public let body: Data?
    /// `Content-Type` header for `body`. `nil` lets the client default to
    /// `application/json` (the shape `.encoding(...)` produces); a multipart
    /// upload sets it explicitly to carry its boundary.
    public let contentType: String?
    /// Extra headers merged onto the request alongside `Content-Type` and the
    /// bearer `Authorization` header — used by the password-session refresh
    /// flow to attach a `Cookie` header, since login itself has no prior
    /// bearer token to authenticate with.
    public let additionalHeaders: [String: String]
    /// Overrides the client's default per-request timeout. `nil` (the
    /// default) lets the session's own timeout apply. Only attachment
    /// upload/download set this, since those transfers can legitimately take
    /// longer than a JSON call on a slow self-hosted connection.
    public let timeoutInterval: TimeInterval?

    /// Timeout for large binary transfers (attachment upload/download) that
    /// may legitimately take longer than a typical JSON call on a slow
    /// self-hosted connection.
    public static let attachmentTransferTimeout: TimeInterval = 60

    public init(
        path: String,
        method: Method = .get,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        additionalHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil,
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
        self.contentType = contentType
        self.additionalHeaders = additionalHeaders
        self.timeoutInterval = timeoutInterval
    }

    static func encoding(
        path: String,
        method: Method,
        queryItems: [URLQueryItem] = [],
        body: some Encodable,
    ) throws -> Endpoint {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try Endpoint(path: path, method: method, queryItems: queryItems, body: encoder.encode(body))
    }

    /// A `multipart/form-data` request built from `form` — used for file
    /// uploads, the one case Vikunja doesn't take a JSON body.
    static func multipart(
        path: String,
        method: Method,
        form: MultipartFormData,
    ) -> Endpoint {
        Endpoint(
            path: path,
            method: method,
            body: form.encoded(),
            contentType: form.contentType,
            timeoutInterval: attachmentTransferTimeout,
        )
    }
}
