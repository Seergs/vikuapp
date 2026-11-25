import Testing
@testable import VikuUI

struct LoadingPresentationTests {
    @Test func `fast completion never shows spinner`() {
        let start = ContinuousClock.now
        var presentation = LoadingPresentation()
        presentation.setLoading(true, now: start)
        presentation.setLoading(false, now: start.advanced(by: .milliseconds(500)))
        presentation.advance(now: start.advanced(by: .seconds(2)))
        #expect(!presentation.isVisible)
        #expect(presentation.nextUpdate == nil)
    }

    @Test func `spinner waits one second then remains until two seconds`() {
        let start = ContinuousClock.now
        var presentation = LoadingPresentation()
        presentation.setLoading(true, now: start)
        presentation.advance(now: start.advanced(by: .milliseconds(999)))
        #expect(!presentation.isVisible)
        presentation.advance(now: start.advanced(by: .seconds(1)))
        #expect(presentation.isVisible)
        presentation.setLoading(false, now: start.advanced(by: .milliseconds(1500)))
        #expect(presentation.isVisible)
        #expect(presentation.nextUpdate == start.advanced(by: .seconds(2)))
        presentation.advance(now: start.advanced(by: .seconds(2)))
        #expect(!presentation.isVisible)
    }

    @Test func `a delayed reveal stays visible for a full second`() {
        let start = ContinuousClock.now
        var presentation = LoadingPresentation()
        presentation.setLoading(true, now: start)
        presentation.advance(now: start.advanced(by: .milliseconds(1200)))
        presentation.setLoading(false, now: start.advanced(by: .milliseconds(1300)))
        #expect(presentation.isVisible)
        #expect(presentation.nextUpdate == start.advanced(by: .milliseconds(2200)))
        presentation.advance(now: start.advanced(by: .milliseconds(2200)))
        #expect(!presentation.isVisible)
    }

    @Test func `slow completion hides spinner immediately after its minimum`() {
        let start = ContinuousClock.now
        var presentation = LoadingPresentation()
        presentation.setLoading(true, now: start)
        presentation.advance(now: start.advanced(by: .seconds(1)))
        presentation.advance(now: start.advanced(by: .seconds(4)))
        #expect(presentation.isVisible)
        presentation.setLoading(false, now: start.advanced(by: .seconds(4)))
        #expect(!presentation.isVisible)
    }

    @Test func `restarting during minimum visibility keeps spinner until completion`() {
        let start = ContinuousClock.now
        var presentation = LoadingPresentation()
        presentation.setLoading(true, now: start)
        presentation.advance(now: start.advanced(by: .seconds(1)))
        presentation.setLoading(false, now: start.advanced(by: .milliseconds(1500)))
        presentation.setLoading(true, now: start.advanced(by: .milliseconds(1600)))
        presentation.advance(now: start.advanced(by: .seconds(3)))
        #expect(presentation.isVisible)
        presentation.setLoading(false, now: start.advanced(by: .seconds(4)))
        #expect(!presentation.isVisible)
    }
}
