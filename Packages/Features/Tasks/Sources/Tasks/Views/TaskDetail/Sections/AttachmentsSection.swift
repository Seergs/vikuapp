import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// The Attachments section: the task's uploaded files, an upload-in-progress
/// row, or an empty/error placeholder. The header's "+ Add" button opens the
/// file importer (disabled while an upload is in flight).
struct AttachmentsSection: View {
    @Bindable var viewModel: TaskDetailViewModel
    let onAdd: () -> Void
    let onOpen: (TaskAttachment) -> Void
    let onDelete: (TaskAttachment) -> Void

    var body: some View {
        SectionBlock(
            title: String(localized: "Attachments", bundle: .module),
            count: viewModel.attachments.isEmpty ? nil : "\(viewModel.attachments.count)",
            trailing: AnyView(
                SectionHeaderButton(title: String(localized: "Add", bundle: .module), action: onAdd)
                    .disabled(viewModel.isUploadingAttachment),
            ),
        ) {
            AttachmentsList(
                attachments: viewModel.attachments,
                loadState: viewModel.attachmentsLoadState,
                isUploading: viewModel.isUploadingAttachment,
                onOpen: onOpen,
                onDelete: onDelete,
            )
        }
    }
}

private struct AttachmentsList: View {
    let attachments: [TaskAttachment]
    let loadState: ScreenLoadState<Void>
    var isUploading = false
    let onOpen: (TaskAttachment) -> Void
    let onDelete: (TaskAttachment) -> Void

    @Environment(\.vikuPalette) private var palette

    private var emptyStateMessage: String {
        if case let .failure(message) = loadState {
            return message
        }
        return String(localized: "No attachments yet.", bundle: .module)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            if attachments.isEmpty, !isUploading {
                Text(verbatim: emptyStateMessage)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(palette.textTertiary)
            } else {
                ForEach(attachments) { attachment in
                    AttachmentRow(
                        attachment: attachment,
                        onOpen: { onOpen(attachment) },
                        onDelete: { onDelete(attachment) },
                    )
                }
            }

            if isUploading {
                AttachmentUploadingRow()
            }
        }
    }
}

private struct AttachmentUploadingRow: View {
    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            ProgressView()
                .frame(width: 28)
            Text("Uploading…", bundle: .module)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
    }
}

private struct AttachmentRow: View {
    let attachment: TaskAttachment
    let onOpen: () -> Void
    let onDelete: () -> Void

    @Environment(\.vikuPalette) private var palette

    private var subtitle: String {
        let size = AttachmentSizeFormatter.string(for: attachment.sizeBytes)
        let date = RelativeTimeFormatter.string(for: attachment.created)
        return "\(size) · \(date)"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: VikuSpacing.sm) {
                Image(systemName: AttachmentIcon.systemName(forMimeType: attachment.mimeType))
                    .font(.system(size: 17))
                    .foregroundStyle(palette.brand)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                    Text(verbatim: attachment.fileName)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            // `role: .destructive` alone renders blue here, same as
            // `CommentRow`'s context menu: the tab bar's brand tint leaks in.
            Button(
                String(localized: "Delete Attachment", bundle: .module),
                systemImage: "trash",
                role: .destructive,
                action: onDelete,
            )
            .tint(palette.semanticDanger)
        }
    }
}
