import Foundation
import Observation

/// Presentation state for a column's inline task creation.
@MainActor
@Observable
final class KanbanTaskDraft {
    var title = ""
    var isPresented = false
    private(set) var isSubmitting = false

    func submit(using create: @MainActor (String) async -> Bool) async {
        let submittedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPresented, !isSubmitting, !submittedTitle.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        guard await create(submittedTitle) else { return }
        title = ""
        isPresented = false
    }
}
