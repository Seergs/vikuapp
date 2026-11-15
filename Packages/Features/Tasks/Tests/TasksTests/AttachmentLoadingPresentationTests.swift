@testable import Tasks
import Testing

struct AttachmentLoadingPresentationTests {
    @Test func `initial and fast loads never show an empty state or spinner`() {
        var presentation = AttachmentLoadingPresentation()
        #expect(presentation.isWaiting)
        #expect(!presentation.showsSpinner)
        #expect(presentation.update(isLoading: true, at: .zero) == .milliseconds(500))
        #expect(presentation.update(isLoading: false, at: .milliseconds(499)) == nil)
        #expect(!presentation.isWaiting)
        #expect(!presentation.showsSpinner)
    }

    @Test func `cached content is ready without waiting for the presentation task`() {
        let presentation = AttachmentLoadingPresentation()
        #expect(!presentation.shouldWait(isLoading: false))
        #expect(presentation.shouldWait(isLoading: true))
    }

    @Test func `only an actually visible spinner can delay ready content`() {
        var presentation = AttachmentLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        #expect(!presentation.shouldWait(isLoading: false))
        _ = presentation.update(isLoading: true, at: .milliseconds(500))
        #expect(presentation.shouldWait(isLoading: false))
        _ = presentation.update(isLoading: false, at: .seconds(2))
        #expect(!presentation.shouldWait(isLoading: false))
    }

    @Test func `spinner appears at half a second and remains visible for at least one second`() {
        var presentation = AttachmentLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        _ = presentation.update(isLoading: true, at: .milliseconds(500))
        #expect(presentation.showsSpinner)
        #expect(presentation.update(isLoading: false, at: .seconds(1)) == .milliseconds(500))
        #expect(presentation.isWaiting)
        #expect(presentation.showsSpinner)
        #expect(presentation.update(isLoading: false, at: .milliseconds(1500)) == nil)
        #expect(!presentation.isWaiting)
        #expect(!presentation.showsSpinner)
    }

    @Test func `slow loads keep the spinner until completion`() {
        var presentation = AttachmentLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        _ = presentation.update(isLoading: true, at: .milliseconds(500))
        #expect(presentation.update(isLoading: true, at: .seconds(4)) == nil)
        #expect(presentation.isWaiting)
        #expect(presentation.showsSpinner)
        _ = presentation.update(isLoading: false, at: .seconds(5))
        #expect(!presentation.isWaiting)
    }

    @Test func `failure follows the same minimum visibility and retry starts fresh`() {
        var presentation = AttachmentLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        _ = presentation.update(isLoading: true, at: .milliseconds(1200))
        #expect(presentation.update(isLoading: false, at: .milliseconds(1300)) == .milliseconds(900))
        _ = presentation.update(isLoading: false, at: .milliseconds(2200))
        #expect(!presentation.isWaiting)
        #expect(presentation.update(isLoading: true, at: .seconds(3)) == .milliseconds(500))
        #expect(presentation.isWaiting)
        #expect(!presentation.showsSpinner)
    }
}
