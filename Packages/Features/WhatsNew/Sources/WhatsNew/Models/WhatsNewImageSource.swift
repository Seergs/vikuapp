import Foundation

/// Keeps the existing JSON compatible with bundled assets and HTTPS delivery URLs.
enum WhatsNewImageSource: Equatable {
    case asset(String)
    case remote(URL)
    case placeholder

    init(_ value: String?) {
        guard let value, !value.isEmpty else {
            self = .placeholder
            return
        }
        if let url = URL(string: value), url.scheme != nil {
            if url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty {
                self = .remote(url)
            } else {
                self = .placeholder
            }
        } else if value.contains("://") || value.hasPrefix("//") {
            self = .placeholder
        } else {
            self = .asset(value)
        }
    }
}
