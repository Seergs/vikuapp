import Foundation
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
    @Bindable var session: CommentEditSession
    private let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vikuPalette) private var palette

    init(session: CommentEditSession, onSave: @escaping (String) -> Void) {
        self.session = session
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TextField(String(localized: "Comment", bundle: .module), text: $session.draft, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .padding(VikuSpacing.sm)
                    .background(
                        palette.cardBackground,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md)
            }
            .navigationTitle(Text("Edit Comment", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) {
                        session.log("save")
                        onSave(session.draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!session.canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { session.log("presented") }
    }
}
