import XCTest

@MainActor
final class UITestApp {
    enum Scenario: String {
        case smoke
        case unauthenticated
        case cached
        case empty
        case multiAccount
        case capabilityLimited
    }

    private enum LaunchMode: String {
        case fresh
        case preferencesOnly
        case resume
    }

    let app = XCUIApplication()
    private let runID = UUID()
    private var scenario: Scenario?
    private var arguments: [String] = []

    @discardableResult
    func launch(
        scenario: Scenario = .smoke,
        preservingPreferences: Bool = false,
        slowReachability: Bool = false,
        additionalArguments: [String] = [],
    ) -> TodayPage {
        self.scenario = scenario
        arguments = additionalArguments
        let mode: LaunchMode = preservingPreferences ? .preferencesOnly : .fresh
        let today = start(scenario, mode: mode, offline: false, slowReachability: slowReachability)
        if scenario == .cached {
            // Warm the SQLite cache through the normal sync path.
            today.assertFixtureVisible()
            return relaunch(offline: true)
        }
        return today
    }

    @discardableResult
    func relaunch(offline: Bool = false) -> TodayPage {
        guard let scenario else { preconditionFailure("Launch a UI test scenario before relaunching it") }
        return start(scenario, mode: .resume, offline: offline, slowReachability: false)
    }

    func terminate() {
        app.terminate()
    }

    private func start(
        _ scenario: Scenario, mode: LaunchMode, offline: Bool, slowReachability: Bool,
    ) -> TodayPage {
        terminate()
        app.launchEnvironment["VIKU_UI_TEST_RUN_ID"] = runID.uuidString
        app.launchEnvironment["VIKU_UI_TEST_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["VIKU_UI_TEST_MODE"] = mode.rawValue
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        if offline {
            app.launchArguments.append("-UITestOffline")
        }
        if slowReachability {
            app.launchArguments.append("-UITestSlowReachability")
        }
        app.launch()
        return TodayPage(app: app)
    }
}
