import Testing
@testable import VikuUI

@MainActor
struct CardDragPresentationTests {
    @Test(arguments: [true, false])
    func `source remains hidden until both drag and destination finish`(dropFinishesFirst: Bool) {
        let presentation = CardDragPresentation()
        presentation.beginDrag(source: "source:42")
        let token = presentation.beginDrop()

        if dropFinishesFirst {
            presentation.finishDrop(token)
        } else {
            presentation.endDrag(source: "source:42", didMove: true)
        }

        #expect(presentation.isSourceHidden("source:42"))
        #expect(!presentation.isSourceHidden("destination:42"))

        if dropFinishesFirst {
            presentation.endDrag(source: "source:42", didMove: true)
        } else {
            // Failure, invalid data and same-column drops restore the source.
            presentation.finishDrop(token)
        }

        #expect(!presentation.isSourceHidden("source:42"))
    }

    @Test func `cancelled or unaccepted drags immediately restore the source`() {
        let presentation = CardDragPresentation()
        presentation.beginDrag(source: "source:42")
        presentation.endDrag(source: "source:42", didMove: false)
        #expect(!presentation.isSourceHidden("source:42"))

        presentation.beginDrag(source: "source:42")
        presentation.endDrag(source: "source:42", didMove: true)
        #expect(!presentation.isSourceHidden("source:42"))
    }

    @Test func `an older completion cannot release another pending drop`() {
        let presentation = CardDragPresentation()
        presentation.beginDrag(source: "source:42")
        let first = presentation.beginDrop()
        presentation.endDrag(source: "source:42", didMove: true)
        presentation.beginDrag(source: "source:43")
        let second = presentation.beginDrop()
        presentation.endDrag(source: "source:43", didMove: true)

        presentation.finishDrop(first)
        #expect(!presentation.isSourceHidden("source:42"))
        #expect(presentation.isSourceHidden("source:43"))
        presentation.finishDrop(first)
        #expect(presentation.isSourceHidden("source:43"))
        presentation.finishDrop(second)
        #expect(!presentation.isSourceHidden("source:43"))
    }

    @Test func `leaving the board resets visibility and ignores late completions`() {
        let presentation = CardDragPresentation()
        #expect(presentation.beginDrop() == nil)
        presentation.beginDrag(source: "source:42")
        let old = presentation.beginDrop()
        presentation.reset()
        #expect(!presentation.isSourceHidden("source:42"))

        presentation.beginDrag(source: "source:42")
        presentation.finishDrop(old)
        #expect(presentation.isSourceHidden("source:42"))
    }
}
