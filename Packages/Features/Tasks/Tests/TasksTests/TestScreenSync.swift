import VikunjaCore

/// Local-only fixture. Tests of refresh inject a controlled trigger instead.
struct TestScreenSync: SyncTriggering, LocalDataObserving {
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {}
    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
