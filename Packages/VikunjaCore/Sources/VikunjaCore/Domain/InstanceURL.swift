import Foundation

/// Normalizes a user-entered instance address — a bare domain
/// (`tasks.example.com`) or a full URL (`https://tasks.example.com`) — into the
/// scheme+host `URL` the networking layer expects as `baseURL`: no path, no
/// trailing slash, no query/fragment, so `Endpoint.path` (which already starts
/// with `/api/v1/...`) appends onto it cleanly.
///
/// HTTPS is the only scheme accepted by default: a bare domain is assumed
/// `https://`, and an explicit `http://` address is rejected with
/// `VikunjaError.insecureInstanceURL` unless `allowInsecureHTTP` is `true`
/// (the connection form's opt-in "insecure connection" toggle).
public enum InstanceURL {
    public static func normalize(_ rawValue: String, allowInsecureHTTP: Bool = false) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VikunjaError.invalidInstanceURL }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: candidate) else {
            throw VikunjaError.invalidInstanceURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw VikunjaError.invalidInstanceURL
        }
        guard let host = components.host, !host.isEmpty else {
            throw VikunjaError.invalidInstanceURL
        }
        guard scheme == "https" || allowInsecureHTTP else {
            throw VikunjaError.insecureInstanceURL
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        guard let url = components.url else { throw VikunjaError.invalidInstanceURL }
        return url
    }
}
