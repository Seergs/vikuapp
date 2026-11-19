import Foundation
@testable import Settings
import Testing

struct NotificationProgressPresentationTests {
    @Test
    func `initial loading shows after half a second and keeps the one second minimum`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation(appearanceDelay: .milliseconds(500))
        progress.update(isActive: true, at: now)
        #expect(progress.nextUpdate == now.advanced(by: .milliseconds(500)))
        progress.advance(at: now.advanced(by: .milliseconds(499)))
        #expect(!progress.isVisible)
        progress.advance(at: now.advanced(by: .milliseconds(500)))
        #expect(progress.isVisible)
        progress.update(isActive: false, at: now.advanced(by: .milliseconds(750)))
        #expect(progress.isVisible)
        #expect(progress.nextUpdate == now.advanced(by: .milliseconds(1500)))
        progress.advance(at: now.advanced(by: .milliseconds(1500)))
        #expect(!progress.isVisible)
    }

    @Test
    func `initial loading completing before half a second never shows progress`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation(appearanceDelay: .milliseconds(500))
        progress.update(isActive: true, at: now)
        progress.update(isActive: false, at: now.advanced(by: .milliseconds(400)))
        progress.advance(at: now.advanced(by: .seconds(1)))
        #expect(!progress.isVisible)
        #expect(progress.nextUpdate == nil)
    }

    @Test
    func `fast or cancelled operations never show the indicator`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation()
        progress.update(isActive: true, at: now)
        progress.update(isActive: false, at: now.advanced(by: .milliseconds(500)))
        progress.advance(at: now.advanced(by: .seconds(2)))
        #expect(!progress.isVisible)
        #expect(progress.nextUpdate == nil)
    }

    @Test
    func `a slow operation shows after one second and stays until completion`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation()
        progress.update(isActive: true, at: now)
        progress.advance(at: now.advanced(by: .milliseconds(999)))
        #expect(!progress.isVisible)
        progress.advance(at: now.advanced(by: .seconds(1)))
        #expect(progress.isVisible)
        progress.advance(at: now.advanced(by: .seconds(4)))
        #expect(progress.isVisible)
        progress.update(isActive: false, at: now.advanced(by: .seconds(5)))
        #expect(!progress.isVisible)
    }

    @Test
    func `completion at one and a half seconds keeps the indicator until two seconds`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation()
        progress.update(isActive: true, at: now)
        progress.advance(at: now.advanced(by: .seconds(1)))
        progress.update(isActive: false, at: now.advanced(by: .milliseconds(1500)))
        #expect(progress.isVisible)
        #expect(progress.nextUpdate == now.advanced(by: .seconds(2)))
        progress.advance(at: now.advanced(by: .seconds(2)))
        #expect(!progress.isVisible)
    }

    @Test
    func `a new operation during the minimum duration keeps the indicator visible`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation()
        progress.update(isActive: true, at: now)
        progress.advance(at: now.advanced(by: .seconds(1)))
        progress.update(isActive: false, at: now.advanced(by: .milliseconds(1200)))
        progress.update(isActive: true, at: now.advanced(by: .milliseconds(1400)))
        progress.advance(at: now.advanced(by: .seconds(3)))
        #expect(progress.isVisible)
        #expect(progress.nextUpdate == nil)
        progress.update(isActive: false, at: now.advanced(by: .seconds(4)))
        #expect(!progress.isVisible)
    }

    @Test
    func `minimum duration starts when the spinner actually appears`() {
        let now = ContinuousClock.now
        var progress = NotificationProgressPresentation()
        progress.update(isActive: true, at: now)
        progress.advance(at: now.advanced(by: .seconds(2)))
        progress.update(isActive: false, at: now.advanced(by: .milliseconds(2100)))
        #expect(progress.isVisible)
        #expect(progress.nextUpdate == now.advanced(by: .seconds(3)))
    }
}
