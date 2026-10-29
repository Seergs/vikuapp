import VikunjaCore
@testable import VikunjaPersistence

/// A deterministic queue driver for repository integration tests. Unlike the
/// production scheduler it finishes the drain before returning, so tests can
/// inspect replay outcomes without sleeps. No query ever invokes this driver.
struct TestSyncRequester: SyncRequesting {
    let engine: SyncEngine
    let reachability: ReachabilityMonitoring

    func requestSync() async {
        guard await reachability.isReachable else { return }
        try? await engine.drainProjectMutations()
        try? await engine.drainLabelMutations()
        try? await engine.drainFilterMutations()
        try? await engine.drainTaskMutations()
        try? await engine.drainCommentMutations()
    }
}
