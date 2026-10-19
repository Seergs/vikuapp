import Foundation
import VikunjaCore

extension InstanceAccount {
    /// Drops the implied `https://` so the host reads first. An insecure
    /// `http://` URL keeps its scheme so the downgrade stays visible.
    var displayHost: String {
        let absolute = baseURL.absoluteString
        let httpsPrefix = "https://"
        guard baseURL.scheme?.lowercased() == "https", absolute.hasPrefix(httpsPrefix) else {
            return absolute
        }
        return String(absolute.dropFirst(httpsPrefix.count))
    }
}
