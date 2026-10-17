import Testing
@testable import VikuNavigation

struct DeepLinkTests {
    @Test
    func `push user info with task id and account key parses to task`() {
        let link = DeepLink(pushUserInfo: ["task_id": 243, "account_key": "account-1", "event": "task.created"])

        #expect(link == .task(id: 243, accountKey: "account-1"))
    }

    @Test
    func `push user info missing task id returns nil`() {
        #expect(DeepLink(pushUserInfo: ["account_key": "account-1"]) == nil)
    }

    @Test
    func `push user info missing account key returns nil`() {
        #expect(DeepLink(pushUserInfo: ["task_id": 243]) == nil)
    }

    @Test
    func `push user info with empty account key returns nil`() {
        #expect(DeepLink(pushUserInfo: ["task_id": 243, "account_key": ""]) == nil)
    }

    @Test
    func `push user info with non numeric task id returns nil`() {
        #expect(DeepLink(pushUserInfo: ["task_id": "not-a-number", "account_key": "account-1"]) == nil)
    }
}
