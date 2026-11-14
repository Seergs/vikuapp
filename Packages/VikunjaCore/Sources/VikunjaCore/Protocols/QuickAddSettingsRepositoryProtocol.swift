/// Local-first access to one account's shared Quick Add Magic preference.
public protocol QuickAddSettingsRepositoryProtocol: Sendable {
    func settings() async throws -> QuickAddMagicSettings
    func setMode(_ mode: QuickAddMagicMode) async throws
    func observeSettings() async -> AsyncThrowingStream<QuickAddMagicSettings, Error>
    func retrySync() async
}
