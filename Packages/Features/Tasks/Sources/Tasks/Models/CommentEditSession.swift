import Foundation
import Observation
import os
import VikuDesignSystem
import VikunjaCore

/// One editor presentation owns both its target and its draft. A reused sheet
/// must bind to the new session rather than retain a previous comment's state.
@MainActor
@Observable
final class CommentEditSession: Identifiable {
    private static let logger = Logger(subsystem: "dev.sergiosuarez.vikunja", category: "comment-order")
    let id = UUID()
    let comment: TaskComment
    let initialText: String
    var draft: String

    init(comment: TaskComment) {
        self.comment = comment
        let text = RichText.plainText(from: comment.comment)
        self.initialText = text
        self.draft = text
        log("selected")
    }

    var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Correlates context-menu selection, presentation, and save without logging text.
    func log(_ event: String) {
        #if DEBUG
        let sessionID = id.uuidString
        let commentID = String(describing: comment.id)
        let draftMatchesInitial = draft == initialText
        Self.logger.debug("[comment-order] editor.\(event, privacy: .public) session=\(sessionID, privacy: .public) comment=\(commentID, privacy: .public) draftMatchesInitial=\(draftMatchesInitial)")
        #endif
    }
}
