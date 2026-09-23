import Foundation

/// v2's RFC 9457 `application/problem+json` error body
/// (`title`/`status`/`detail`/`code`). v1 has no equivalent — its error
/// bodies are ad hoc and get surfaced as raw text instead.
struct ProblemDetailDTO: Decodable {
    let title: String?
    let status: Int?
    let detail: String?
    let code: String?
}

extension ProblemDetailDTO {
    /// A single human-readable line built from a v2 problem-detail body, for
    /// `VikunjaError.server`'s `message` — `nil` when `data` isn't a
    /// problem-detail JSON object (or carries neither `title` nor `detail`),
    /// so the caller can fall back to the raw body text.
    static func message(from data: Data) -> String? {
        guard let problem = try? JSONDecoder().decode(ProblemDetailDTO.self, from: data) else { return nil }

        var parts: [String] = []
        if let title = problem.title {
            parts.append(title)
        }
        if let detail = problem.detail {
            parts.append(detail)
        }
        guard !parts.isEmpty else { return nil }

        var message = parts.joined(separator: ": ")
        if let code = problem.code {
            message += " (\(code))"
        }
        return message
    }
}
