import Foundation

/// Loads images embedded in rich text for one account: attachments through the
/// authenticated attachment endpoint, other `https` images through
/// `fetchRemote` (which must not send credentials).
///
/// Results stay in memory only, bounded by `cacheCostLimit` bytes and evicted
/// under memory pressure. Concurrent requests for the same image share one
/// download, so a description and a comment showing the same picture fetch
/// it once.
public actor InlineImageLoader: InlineImageLoading {
    public typealias RemoteFetch = @Sendable (URL) async throws -> Data

    private struct Key: Hashable {
        let source: InlineImageSource
        let variant: InlineImageVariant

        var cacheKey: NSString {
            NSString(string: "\(source)|\(variant)")
        }
    }

    private let instanceURL: URL
    private let attachmentRepository: TaskAttachmentRepositoryProtocol
    private let fetchRemote: RemoteFetch
    private let cache = NSCache<NSString, NSData>()
    private var inFlight: [Key: Task<Data, Error>] = [:]

    public init(
        instanceURL: URL,
        attachmentRepository: TaskAttachmentRepositoryProtocol,
        cacheCostLimit: Int = 48 * 1024 * 1024,
        fetchRemote: @escaping RemoteFetch,
    ) {
        self.instanceURL = instanceURL
        self.attachmentRepository = attachmentRepository
        self.fetchRemote = fetchRemote
        cache.totalCostLimit = cacheCostLimit
    }

    public func imageData(for source: String, variant: InlineImageVariant) async throws -> Data {
        guard let resolved = InlineImageSource.resolve(source, instanceURL: instanceURL) else {
            throw InlineImageLoadingError.unsupportedSource
        }
        // A remote image has a single rendition, so both variants share it.
        let key = Key(source: resolved, variant: resolved.isAttachment ? variant : .original)

        if let cached = cachedData(for: key) {
            return cached
        }

        let task: Task<Data, Error>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task { try await self.download(key) }
            inFlight[key] = task
        }

        do {
            let data = try await task.value
            inFlight[key] = nil
            cache.setObject(data as NSData, forKey: key.cacheKey, cost: data.count)
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// A cached original is good enough for display; it's the same picture,
    /// just bigger, and it saves a request.
    private func cachedData(for key: Key) -> Data? {
        if let data = cache.object(forKey: key.cacheKey) {
            return data as Data
        }
        if key.variant == .display,
           let original = cache.object(forKey: Key(source: key.source, variant: .original).cacheKey) {
            return original as Data
        }
        return nil
    }

    private func download(_ key: Key) async throws -> Data {
        switch key.source {
        case let .remote(url):
            return try await fetchRemote(url)

        case let .attachment(taskID, attachmentID):
            guard key.variant == .display else {
                return try await attachmentRepository.downloadAttachment(
                    attachmentID, fromTask: taskID, previewSize: nil,
                )
            }
            do {
                return try await attachmentRepository.downloadAttachment(
                    attachmentID, fromTask: taskID, previewSize: .xl,
                )
            } catch {
                // The server only renders previews for images up to 50 MB;
                // anything else it rejects is worth one try at the original.
                // Connectivity and auth failures would fail the same way again.
                guard Self.previewFailureAllowsFallback(error) else { throw error }
                return try await attachmentRepository.downloadAttachment(
                    attachmentID, fromTask: taskID, previewSize: nil,
                )
            }
        }
    }

    private static func previewFailureAllowsFallback(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        switch error as? VikunjaError {
        case .offline, .network, .timeout, .unauthorized, .sessionExpired:
            return false
        default:
            return true
        }
    }
}

private extension InlineImageSource {
    var isAttachment: Bool {
        if case .attachment = self {
            return true
        }
        return false
    }
}
