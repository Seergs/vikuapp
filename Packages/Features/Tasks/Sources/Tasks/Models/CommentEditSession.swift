import Foundation
import Observation
import VikuDesignSystem
import VikunjaCore

/// One editor presentation owns both its target and its draft. A reused sheet
/// must bind to the new session rather than retain a previous comment's state.
@MainActor
@Observable
final class CommentEditSession: Identifiable {
    let id = UUID()
    let comment: TaskComment
    let initialText: String
    var draft: String

    init(comment: TaskComment) {
        self.comment = comment
        let text = RichText.plainText(from: comment.comment)
        self.initialText = text
        self.draft = text
    }

    var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
