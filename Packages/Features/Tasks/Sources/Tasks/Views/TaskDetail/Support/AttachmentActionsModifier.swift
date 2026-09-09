import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import VikunjaCore

/// The attachment file-importer, QuickLook preview, and delete confirmation,
/// grouped off `TaskDetailView.body` — its modifier chain is long enough that
/// folding these in inline pushes the type-checker past its time budget.
struct AttachmentActionsModifier: ViewModifier {
    @Bindable var viewModel: TaskDetailViewModel
    @Binding var isShowingFileImporter: Bool
    @Binding var pendingDeletion: TaskAttachment?
    @Binding var previewURL: URL?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                Task { await viewModel.attachFile(at: url) }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog(
                "This permanently deletes the attachment.",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: {
                        if !$0 {
                            pendingDeletion = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion,
            ) { attachment in
                Button("Delete Attachment", role: .destructive) {
                    Task { await viewModel.deleteAttachment(attachment) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
