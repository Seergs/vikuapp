#if DEBUG
import Foundation
import VikunjaCore

nonisolated enum UITestScenario: String, Codable {
    case smoke
    case unauthenticated
    case cached
    case empty
    case multiAccount
    case capabilityLimited

    var instances: [InstanceAccount] {
        let primary = Self.account(number: 1, name: "UI Test Account", host: "ui-testing.invalid")
        if self == .multiAccount {
            return [primary, Self.account(number: 2, name: "UI Test Second Account", host: "second.ui-testing.invalid")]
        }
        return [primary]
    }

    var version: String {
        self == .capabilityLimited ? "0.24.6" : "2.4.0"
    }

    private static func account(number: UInt8, name: String, host: String) -> InstanceAccount {
        guard let url = URL(string: "https://\(host)") else { fatalError("Invalid UI testing instance URL") }
        return InstanceAccount(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number)),
            displayName: name,
            baseURL: url,
            createdAt: Date(timeIntervalSince1970: 0),
        )
    }
}

/// Catalog entries shared by the fake server's repositories.
nonisolated enum UITestFixtures {
    static let navigationLabel = Label(id: 1, title: "UI Test Navigation", hexColor: "4986A2")
    static let savedFilterProject = Project(id: -2, title: "UI Test Saved Filter")

    static func tasks(secondInstance: Bool) -> [VikunjaTask] {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        if secondInstance {
            return [VikunjaTask(id: 1, title: "UI Test: Second account task", dueDate: noon, projectID: 1)]
        }
        return [
            VikunjaTask(
                id: 1, title: "UI Test: Plan today", dueDate: noon, priority: .high, projectID: 1,
                labels: [navigationLabel],
            ),
            VikunjaTask(
                id: 2, title: "UI Test: Review overdue",
                dueDate: calendar.date(byAdding: .day, value: -1, to: noon), projectID: 1,
            ),
        ]
    }
}
#endif
