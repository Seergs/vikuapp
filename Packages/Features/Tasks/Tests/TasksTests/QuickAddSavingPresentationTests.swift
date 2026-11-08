@testable import Tasks
import Testing

struct QuickAddSavingPresentationTests {
    @Test func `fast saves never show the spinner`() {
        var presentation = QuickAddSavingPresentation()
        #expect(presentation.update(isSaving: true, at: .zero) == .seconds(1))
        #expect(!presentation.isVisible)
        #expect(presentation.update(isSaving: false, at: .milliseconds(999)) == nil)
        #expect(!presentation.isVisible)
    }

    @Test func `a save completing at one and a half seconds keeps the spinner until two seconds`() {
        var presentation = QuickAddSavingPresentation()
        _ = presentation.update(isSaving: true, at: .zero)
        _ = presentation.update(isSaving: true, at: .seconds(1))
        #expect(presentation.isVisible)
        #expect(presentation.update(isSaving: false, at: .milliseconds(1500)) == .milliseconds(500))
        #expect(presentation.isVisible)
        #expect(presentation.update(isSaving: false, at: .seconds(2)) == nil)
        #expect(!presentation.isVisible)
    }

    @Test func `slow saves keep the spinner until the operation completes`() {
        var presentation = QuickAddSavingPresentation()
        _ = presentation.update(isSaving: true, at: .zero)
        _ = presentation.update(isSaving: true, at: .seconds(1))
        #expect(presentation.update(isSaving: true, at: .seconds(3)) == nil)
        #expect(presentation.isVisible)
        #expect(presentation.update(isSaving: false, at: .seconds(4)) == nil)
        #expect(!presentation.isVisible)
    }

    @Test func `failure or cancellation resets timing for a retry`() {
        var presentation = QuickAddSavingPresentation()
        _ = presentation.update(isSaving: true, at: .zero)
        _ = presentation.update(isSaving: false, at: .milliseconds(100))
        #expect(presentation.update(isSaving: true, at: .seconds(5)) == .seconds(1))
        #expect(!presentation.isVisible)
        _ = presentation.update(isSaving: true, at: .seconds(6))
        #expect(presentation.isVisible)
        _ = presentation.update(isSaving: false, at: .seconds(7))
        #expect(!presentation.isVisible)
    }

    @Test func `delayed spinner appearance still gets a full second on screen`() {
        var presentation = QuickAddSavingPresentation()
        _ = presentation.update(isSaving: true, at: .zero)
        _ = presentation.update(isSaving: true, at: .milliseconds(1200))
        #expect(presentation.update(isSaving: false, at: .milliseconds(1300)) == .milliseconds(900))
        #expect(presentation.isVisible)
        _ = presentation.update(isSaving: false, at: .milliseconds(2200))
        #expect(!presentation.isVisible)
    }
}
