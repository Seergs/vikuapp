import Foundation
@testable import Tasks
import Testing
import VikunjaCore

@MainActor
struct CommentEditSessionTests {
    private func comment(_ id: Int, _ text: String) -> TaskComment {
        TaskComment(
            id: .remote(id), comment: text, author: User(id: 1, username: "me"),
            created: Date(timeIntervalSince1970: 1_700_000_000),
            updated: Date(timeIntervalSince1970: 1_700_000_100),
        )
    }

    @Test func `repeatedly switching between edited comments keeps each draft with its target`() {
        let comments = [comment(1, "ONE edited"), comment(2, "TWO edited"), comment(3, "THREE original")]
        var previous: CommentEditSession?
        for index in [0, 2, 1, 0, 2, 1, 0, 2, 1] {
            let selected = comments[index]
            let session = CommentEditSession(comment: selected)
            #expect(session.comment.id == selected.id)
            #expect(session.draft == selected.comment)
            #expect(!session.canSave)
            #expect(session.id != previous?.id)
            session.draft = "Unsaved change to \(selected.id)"
            previous = session
        }
    }

    @Test func `reopening the same comment discards the cancelled draft and uses its current text`() {
        var selected = comment(1, "Original")
        let cancelled = CommentEditSession(comment: selected)
        cancelled.draft = "Cancelled draft"
        selected.comment = "Updated on another client"

        let reopened = CommentEditSession(comment: selected)
        #expect(reopened.id != cancelled.id)
        #expect(reopened.comment.id == cancelled.comment.id)
        #expect(reopened.draft == "Updated on another client")
        #expect(!reopened.canSave)
    }

    @Test func `refreshing source comments does not replace an open draft or its target`() {
        var selected = comment(2, "<p>TWO <strong>edited</strong></p>")
        let session = CommentEditSession(comment: selected)
        #expect(session.draft == "TWO edited")
        session.draft = "In progress"
        selected.comment = "Remote update"

        #expect(session.comment.id == .remote(2))
        #expect(session.draft == "In progress")
        #expect(session.initialText == "TWO edited")
        #expect(session.canSave)
    }

    @Test func `save requires a nonblank change from the selected comments initial text`() {
        let session = CommentEditSession(comment: comment(1, "<p>Original</p>"))
        for draft in ["", " \n ", "Original", " Original\n"] {
            session.draft = draft
            #expect(!session.canSave)
        }
        session.draft = "Revised"
        #expect(session.canSave)
    }
}
