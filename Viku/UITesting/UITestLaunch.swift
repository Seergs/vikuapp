import Foundation
import VikunjaPersistence

extension AppContainer {
    /// The launch switch and its fixtures are absent from release builds.
    static func forLaunch() -> AppContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VikuUITesting")
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
                let suite = "dev.sergiosuarez.viku.uitesting"
                guard let defaults = UserDefaults(suiteName: suite) else {
                    fatalError("Cannot open UI testing preferences")
                }
                if !ProcessInfo.processInfo.arguments.contains("-UITestPreservePreferences") {
                    defaults.removePersistentDomain(forName: suite)
                }
                return AppContainer(
                    accountStore: UITestAccountStore(),
                    clientFactory: UITestClientFactory(),
                    localStoreDirectory: directory,
                    defaults: defaults,
                    reachabilityMonitor: UITestReachability(),
                    isUITesting: true,
                )
            } catch {
                fatalError("Cannot prepare isolated UI testing state: \(error)")
            }
        }
        #endif
        return AppContainer()
    }
}

#if DEBUG
/// Reachability describes the in-process fake server, not the simulator's Wi-Fi.
nonisolated struct UITestReachability: ReachabilityMonitoring {
    var isReachable: Bool {
        true
    }

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func reachabilityUpdates() async -> AsyncStream<Bool> {
        if ProcessInfo.processInfo.arguments.contains("-UITestSlowReachability") {
            try? await Task.sleep(for: .seconds(6))
        }
        return AsyncStream { continuation in
            continuation.yield(true)
            continuation.finish()
        }
    }
}
#endif
