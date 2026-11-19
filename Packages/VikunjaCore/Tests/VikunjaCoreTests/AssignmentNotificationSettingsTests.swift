import Foundation
import Testing
@testable import VikunjaCore

struct AssignmentNotificationSettingsTests {
    @Test
    func `older saved settings decode without losing their events`() throws {
        let json = #"{"isEnabled":true,"userLevelEvents":[],"projectEvents":{"4":["task.assignee.created"]}}"#
        let data = Data(json.utf8)
        let settings = try JSONDecoder().decode(NotificationSettings.self, from: data)
        #expect(settings.isEnabled)
        #expect(settings.events(for: 4) == [.taskAssigneeCreated])
        #expect(settings.assignmentMode(for: 4) == .all)
    }

    @Test
    func `confirmed modes survive encoding and remain scoped by project`() throws {
        let settings = NotificationSettings(projectAssignmentModes: [4: .onlyMe, 5: .all])
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.assignmentMode(for: 4) == .onlyMe)
        #expect(decoded.assignmentMode(for: 5) == .all)
        #expect(decoded.assignmentMode(for: 6) == .all)
    }
}
