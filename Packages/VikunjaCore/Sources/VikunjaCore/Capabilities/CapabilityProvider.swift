public protocol CapabilityProvider: Sendable {
    func serverInfo() async throws -> VikunjaServerInfo
    func supports(_ feature: VikunjaFeature) async -> Bool
}

/// A `CapabilityProvider` that reports no feature as supported. The default
/// for previews and for any view model collaborator that doesn't gate on a
/// real server's capabilities in its tests, mirroring `NoopToastPresenter`/
/// `NoopHapticFeedback` — fails closed (a feature stays hidden) rather than
/// crashing when nothing more specific is wired in.
public struct NoopCapabilityProvider: CapabilityProvider {
    public init() {}

    public func serverInfo() async throws -> VikunjaServerInfo {
        throw VikunjaError.notFound
    }

    public func supports(_: VikunjaFeature) async -> Bool {
        false
    }
}
