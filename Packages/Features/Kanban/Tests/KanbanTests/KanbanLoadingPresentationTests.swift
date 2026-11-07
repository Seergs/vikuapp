@testable import Kanban
import Testing

struct KanbanLoadingPresentationTests {
    @Test func `fast download never shows a spinner`() {
        var presentation = KanbanLoadingPresentation()
        #expect(presentation.update(isLoading: true, at: .zero) == .milliseconds(500))
        #expect(!presentation.isVisible)
        #expect(presentation.update(isLoading: false, at: .milliseconds(499)) == nil)
        #expect(!presentation.isVisible)
    }

    @Test func `spinner starts at half a second and remains for a full second after appearing`() {
        var presentation = KanbanLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        _ = presentation.update(isLoading: true, at: .milliseconds(500))
        #expect(presentation.isVisible)
        #expect(presentation.update(isLoading: false, at: .milliseconds(700)) == .milliseconds(800))
        #expect(presentation.isVisible)
        #expect(presentation.update(isLoading: false, at: .milliseconds(1500)) == nil)
        #expect(!presentation.isVisible)
    }

    @Test func `slow download keeps spinner until completion`() {
        var presentation = KanbanLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        _ = presentation.update(isLoading: true, at: .milliseconds(500))
        #expect(presentation.update(isLoading: true, at: .seconds(5)) == nil)
        #expect(presentation.isVisible)
        _ = presentation.update(isLoading: false, at: .seconds(6))
        #expect(!presentation.isVisible)
    }

    @Test func `leaving the screen resets timing for the next visit`() {
        var presentation = KanbanLoadingPresentation()
        _ = presentation.update(isLoading: true, at: .zero)
        _ = presentation.update(isLoading: true, at: .seconds(1))
        presentation = KanbanLoadingPresentation()
        #expect(!presentation.isVisible)
        #expect(presentation.update(isLoading: true, at: .seconds(2)) == .milliseconds(500))
    }
}
