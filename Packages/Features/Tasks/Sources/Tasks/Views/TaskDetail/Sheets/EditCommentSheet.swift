import SwiftUI
import VikuDesignSystem

/// Edits an existing comment's body. A small sheet with a "Save" toolbar
/// button, matching `DueDatePickerSheet`'s pattern rather than the inline
/// edit the task title/description use — `CommentRow` is a nested private
/// view with no toolbar of its own to host a commit affordance. The field
/// starts from the comment's plain-text form (Vikunja stores the body as the
/// web editor's HTML; see `RichText.plainText(from:)`), and `onSave` sends
/// plain text back the same way the composer does for a new comment.
struct EditCommentSheet: View {
    @State private var draft: String
    private let initialText: String
    private let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initialText: String, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        _draft = State(initialValue: initialText)
        self.onSave = onSave
    }

    private var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TextField("Comment", text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .padding(VikuSpacing.sm)
                    .background(
                        VikuColor.Surface.card,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md)
            }
            .navigationTitle("Edit Comment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
