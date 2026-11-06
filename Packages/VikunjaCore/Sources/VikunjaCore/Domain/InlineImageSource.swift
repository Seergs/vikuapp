import Foundation

/// Where an image embedded in a rich-text field (task description, comment)
/// can be loaded from.
///
/// Vikunja's web editor uploads a pasted image as an attachment of the task and
/// stores `<img data-src="{instance}/api/v1/tasks/{id}/attachments/{id}" src="#">`.
/// The attachment needs the user's token, so it has to go through the
/// authenticated download endpoint. Any other `https` image is public and is
/// fetched without credentials.
public enum InlineImageSource: Hashable, Sendable {
    case attachment(taskID: Int, attachmentID: Int)
    case remote(URL)

    /// Classifies the raw `src` of an embedded image against the instance it
    /// came from. Returns `nil` when the image can't be loaded safely:
    /// non-`https` remote images, and attachment URLs that point at a
    /// different instance (sending this account's token there would leak it).
    ///
    /// Mirrors the web frontend's rule: the version segment (`/api/v1`,
    /// `/api/v2`, or none) is matched, not compared, so descriptions written
    /// before the v2 switch keep working. Paths starting with `/` are
    /// resolved against the instance, since a same-origin web deployment
    /// stores them relative.
    public static func resolve(_ source: String, instanceURL: URL) -> InlineImageSource? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "#",
              let instance = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false),
              let components = absoluteComponents(for: trimmed, instance: instance)
        else { return nil }

        if let reference = attachmentReference(inPath: components.percentEncodedPath) {
            let sameInstance = sameOrigin(components, instance)
                && normalizedRoot(reference.root) == normalizedRoot(instance.percentEncodedPath)
            return sameInstance
                ? .attachment(taskID: reference.taskID, attachmentID: reference.attachmentID)
                : nil
        }

        guard components.scheme?.lowercased() == "https", let url = components.url else {
            return nil
        }
        return .remote(url)
    }

    private static func absoluteComponents(for source: String, instance: URLComponents) -> URLComponents? {
        if source.hasPrefix("/"), !source.hasPrefix("//") {
            var resolved = instance
            guard let relative = URLComponents(string: source) else { return nil }
            resolved.percentEncodedPath = relative.percentEncodedPath
            resolved.percentEncodedQuery = relative.percentEncodedQuery
            resolved.fragment = nil
            return resolved
        }
        guard let components = URLComponents(string: source), components.host != nil else {
            return nil
        }
        return components
    }

    private struct AttachmentReference {
        let root: String
        let taskID: Int
        let attachmentID: Int
    }

    /// Splits `{root}[/api/v1|/api/v2]/tasks/{taskID}/attachments/{attachmentID}`.
    private static func attachmentReference(inPath path: String) -> AttachmentReference? {
        var segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.last?.isEmpty == true {
            segments.removeLast()
        }
        guard segments.count >= 4,
              segments[segments.count - 4] == "tasks",
              segments[segments.count - 2] == "attachments",
              let taskID = Int(segments[segments.count - 3]), taskID > 0,
              let attachmentID = Int(segments[segments.count - 1]), attachmentID > 0
        else { return nil }

        var rootSegments = Array(segments.dropLast(4))
        if rootSegments.count >= 2,
           rootSegments[rootSegments.count - 2] == "api",
           ["v1", "v2"].contains(rootSegments[rootSegments.count - 1]) {
            rootSegments.removeLast(2)
        }
        return AttachmentReference(
            root: rootSegments.joined(separator: "/"),
            taskID: taskID,
            attachmentID: attachmentID,
        )
    }

    private static func sameOrigin(_ lhs: URLComponents, _ rhs: URLComponents) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    /// The instance URL may be stored with a trailing slash or a legacy
    /// `/api/v1` suffix; neither changes which instance it is.
    private static func normalizedRoot(_ path: String) -> String {
        var root = path
        while root.hasSuffix("/") {
            root.removeLast()
        }
        for suffix in ["/api/v1", "/api/v2"] where root.hasSuffix(suffix) {
            root.removeLast(suffix.count)
        }
        return root
    }
}
