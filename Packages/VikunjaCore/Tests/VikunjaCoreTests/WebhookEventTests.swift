import Testing
import VikunjaCore

/// `projectOrdered`/`userDirected` encode an asymmetric server rule (see
/// their doc comments): a user-level webhook is restricted to
/// `userDirected`, but a project-level webhook isn't restricted away from
/// it — `task.overdue`/`task.reminder.fired` are valid project webhook
/// events too. Regression coverage for that asymmetry, since it's easy to
/// assume (incorrectly) that `projectOrdered` is `allCases` minus
/// `userDirected`.
struct WebhookEventTests {
    @Test
    func `projectOrdered includes the user directed events too`() {
        #expect(Set(WebhookEvent.projectOrdered) == Set(WebhookEvent.allCases))
        #expect(WebhookEvent.projectOrdered.contains(.taskOverdue))
        #expect(WebhookEvent.projectOrdered.contains(.taskReminderFired))
    }

    @Test
    func `userDirected only contains the two events a user level webhook may use`() {
        #expect(WebhookEvent.userDirected == [.taskOverdue, .taskReminderFired])
    }
}
