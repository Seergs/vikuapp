import Foundation
import VikunjaCore

/// Separate from recovery codes: adding diagnostics must never change replay eligibility.
/// Keep the original detail for tester reports and resolve display copy when reading the queue.
struct StoredSyncFailure: Codable, Sendable {
    enum Kind: String, Codable {
        case server
        case unauthorized
        case notFound
        case bucketFull
        case offline
        case network
        case timeout
        case decoding
        case sessionExpired
        case other
    }

    let kind: Kind
    let detail: String
    let statusCode: Int?
    let occurredAt: Date

    init(error: any Error, occurredAt: Date = Date()) {
        self.occurredAt = occurredAt
        var code: Int?
        switch error {
        case let VikunjaError.server(message, statusCode):
            self.kind = .server
            self.detail = message
            code = statusCode
        case VikunjaError.unauthorized:
            self.kind = .unauthorized
            self.detail = String(describing: error)
        case VikunjaError.notFound:
            self.kind = .notFound
            self.detail = String(describing: error)
        case VikunjaError.bucketFull:
            self.kind = .bucketFull
            self.detail = String(describing: error)
        case VikunjaError.offline:
            self.kind = .offline
            self.detail = String(describing: error)
        case let VikunjaError.network(message):
            self.kind = .network
            self.detail = message
        case VikunjaError.timeout:
            self.kind = .timeout
            self.detail = String(describing: error)
        case let VikunjaError.decoding(message):
            self.kind = .decoding
            self.detail = message
        case VikunjaError.sessionExpired:
            self.kind = .sessionExpired
            self.detail = String(describing: error)
        default:
            self.kind = .other
            self.detail = String(describing: error)
        }
        self.statusCode = code
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(_ value: String?) -> Self? {
        value.flatMap { try? JSONDecoder().decode(Self.self, from: Data($0.utf8)) }
    }

    var displayMessage: String {
        switch kind {
        case .server:
            // v1 returns JSON as raw text; v2 problem details are already readable.
            let body = (try? JSONSerialization.jsonObject(with: Data(detail.utf8))) as? [String: Any]
            let message = (body?["message"] as? String) ?? detail
            let description = VikunjaError.server(message: message, statusCode: statusCode ?? 0).displayMessage
            return statusCode.map { "HTTP \($0): \(description)" } ?? description
        case .unauthorized: return VikunjaError.unauthorized.displayMessage
        case .notFound:
            return String(localized: "The item is no longer available.", bundle: .module)
        case .bucketFull: return VikunjaError.bucketFull.displayMessage
        case .offline: return VikunjaError.offline.displayMessage
        case .network: return VikunjaError.network(detail).displayMessage
        case .timeout: return VikunjaError.timeout.displayMessage
        case .sessionExpired: return VikunjaError.sessionExpired.displayMessage
        case .decoding:
            return String(localized: "The server response could not be read.", bundle: .module)
        case .other:
            return Self.unknownMessage
        }
    }

    static var unknownMessage: String {
        String(
            localized: "This change could not be synced.",
            bundle: .module,
        )
    }

    var diagnosticDetails: String {
        var lines = ["Last failure: \(occurredAt.ISO8601Format())", "Error kind: \(kind.rawValue)"]
        if let statusCode {
            lines.append("HTTP status: \(statusCode)")
        }
        lines.append(detail)
        return lines.joined(separator: "\n")
    }
}
