/// Discards an account's unsynced changes only after a complete server download.
/// Failure or cancellation before the atomic replacement preserves local data.
public protocol AccountReloading: Sendable {
    func reloadFromServer() async throws
}
