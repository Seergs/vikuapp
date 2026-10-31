import Testing
import VikunjaCore
import VikuUI

struct TaskCompletionStateTests {
    private let task = VikunjaTask(id: 1, title: "Task", projectID: 1)

    @Test
    func `snapshots keep pending completion while accepting refreshed metadata`() throws {
        var state = TaskCompletionState()
        let pending = state.begin(task)
        _ = try #require(pending)
        var refreshed = task
        refreshed.title = "Renamed elsewhere"
        let visible = state.applying(to: [refreshed])
        #expect(visible.first?.isDone == true)
        #expect(visible.first?.title == refreshed.title)
    }

    @Test
    func `different tasks remain independent and repeated taps do not start duplicate writes`() throws {
        var state = TaskCompletionState()
        let pending = state.begin(task)
        let first = try #require(pending)
        let other = VikunjaTask(id: 2, title: "Other", projectID: 1)
        let otherPending = state.begin(other)
        _ = try #require(otherPending)
        #expect(state.begin(task) == nil)
        #expect(state.begin(first) == nil)
        var visible = state.applying(to: [task, other])
        state.resolve(first, in: &visible)
        #expect(state.applying(to: [other]).first?.isDone == true)
        #expect(state.begin(first)?.isDone == false)
    }

    @Test(arguments: [true, false])
    func `success and rollback preserve unrelated refreshed fields`(succeeds: Bool) throws {
        var state = TaskCompletionState()
        let pending = state.begin(task)
        let flipped = try #require(pending)
        var refreshed = task
        refreshed.title = "Renamed elsewhere"
        var visible = state.applying(to: [refreshed])
        state.resolve(succeeds ? flipped : task, in: &visible)
        #expect(visible.first?.isDone == succeeds)
        #expect(visible.first?.title == refreshed.title)
        #expect(state.applying(to: [task]) == [task])
    }

    @Test
    func `a removed task is never reinserted by a pending edit or its response`() throws {
        var state = TaskCompletionState()
        let pending = state.begin(task)
        let flipped = try #require(pending)
        var visible = state.applying(to: [])
        state.resolve(flipped, in: &visible)
        #expect(visible.isEmpty)
        #expect(state.begin(task) != nil)
    }

    @Test
    func `an unchanged row accepts the complete repository response`() throws {
        var state = TaskCompletionState()
        let pending = state.begin(task)
        var result = try #require(pending)
        var visible = [result]
        result.title = "Repository result"
        state.resolve(result, in: &visible)
        #expect(visible == [result])
    }
}
