import Foundation
import VikunjaPersistence
import VikuWidgetKit

extension AppContainer {
    /// The launch switch and its fixtures are absent from release builds.
    static func forLaunch() -> AppContainer {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-UITesting") {
            do {
                return try makeUITestContainer(process: process)
            } catch {
                fatalError("Cannot prepare isolated UI testing state: \(error)")
            }
        }
        #endif
        return AppContainer()
    }

    #if DEBUG
    private static func makeUITestContainer(process: ProcessInfo) throws -> AppContainer {
        let launch = try UITestLaunchConfiguration(environment: process.environment)
        try launch.prepareDirectory()
        guard let defaults = UserDefaults(suiteName: launch.suite) else {
            fatalError("Cannot open UI testing preferences")
        }
        if launch.mode == .fresh {
            defaults.removePersistentDomain(forName: launch.suite)
        }
        return try AppContainer(
            accountStore: UITestAccountStore(directory: launch.directory, seed: launch.seed),
            clientFactory: UITestClientFactory(
                directory: launch.directory, scenario: launch.scenario, resetsState: launch.mode != .resume,
            ),
            localStoreDirectory: launch.localStoreDirectory,
            defaults: defaults,
            reachabilityMonitor: UITestReachability(
                isReachable: !process.arguments.contains("-UITestOffline"),
                delaysInitialUpdate: process.arguments.contains("-UITestSlowReachability"),
            ),
            isUITesting: true,
            appIconBadgePreference: AppIconBadgePreference(suiteName: launch.suite),
        )
    }
    #endif
}

#if DEBUG
private struct UITestLaunchConfiguration {
    private enum ConfigurationError: Error {
        case invalidEnvironment
        case scenarioMismatch
        case missingLocalDatabase
    }

    enum Mode: String {
        case fresh
        case preferencesOnly
        case resume
    }

    let directory: URL
    let suite: String
    let mode: Mode
    let scenario: UITestScenario

    var localStoreDirectory: URL {
        directory.appendingPathComponent("LocalStore", isDirectory: true)
    }

    var seed: UITestScenario? {
        mode == .resume ? nil : scenario
    }

    init(environment: [String: String]) throws {
        guard let mode = Mode(rawValue: environment["VIKU_UI_TEST_MODE"] ?? "fresh"),
              let scenario = UITestScenario(rawValue: environment["VIKU_UI_TEST_SCENARIO"] ?? "smoke"),
              let id = UUID(uuidString: environment["VIKU_UI_TEST_RUN_ID"] ?? UUID().uuidString)
        else { throw ConfigurationError.invalidEnvironment }

        self.mode = mode
        self.scenario = scenario
        self.suite = "dev.sergiosuarez.viku.uitesting.\(id.uuidString)"
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VikuUITesting", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func prepareDirectory() throws {
        let manager = FileManager.default
        let manifest = UITestStateFile<UITestScenario>(url: directory.appendingPathComponent("scenario.json"))
        if mode == .resume {
            guard try manifest.load(seed: nil) == scenario else {
                throw ConfigurationError.scenarioMismatch
            }
            guard manager.fileExists(atPath: localStoreDirectory.appendingPathComponent("viku.sqlite").path) else {
                throw ConfigurationError.missingLocalDatabase
            }
            return
        }
        if manager.fileExists(atPath: directory.path) {
            try manager.removeItem(at: directory)
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try manifest.load(seed: scenario)
    }
}

/// Reachability describes the in-process fake server, not the simulator's Wi-Fi.
nonisolated struct UITestReachability: ReachabilityMonitoring {
    let isReachable: Bool
    let delaysInitialUpdate: Bool

    func reachabilityRegained() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func reachabilityUpdates() async -> AsyncStream<Bool> {
        if delaysInitialUpdate {
            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return AsyncStream { $0.finish() }
            }
        }
        return AsyncStream { continuation in
            continuation.yield(isReachable)
            continuation.finish()
        }
    }
}
#endif
