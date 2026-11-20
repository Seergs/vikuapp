import Foundation
import Testing
@testable import VikunjaCore

struct OverdueNotificationSettingsTests {
    @Test
    func `settings without grouping decode as ungrouped without losing selections`() throws {
        let json = #"{"isEnabled":true,"userLevelEvents":["tasks.overdue"],"projectEvents":{}}"#
        let settings = try JSONDecoder().decode(NotificationSettings.self, from: Data(json.utf8))
        #expect(!settings.groupOverdueNotifications)
        #expect(settings.isEnabled)
        #expect(settings.userLevelEvents == [.tasksOverdue])
    }

    @Test
    func `different connection choices survive persistence independently`() throws {
        let workID = UUID().uuidString
        let personalID = UUID().uuidString
        let settings = [
            workID: NotificationSettings(isEnabled: true, groupOverdueNotifications: true),
            personalID: NotificationSettings(isEnabled: true, groupOverdueNotifications: false),
        ]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode([String: NotificationSettings].self, from: data)
        #expect(decoded == settings)
        #expect(decoded[workID]?.groupOverdueNotifications == true)
        #expect(decoded[personalID]?.groupOverdueNotifications == false)
    }
}
