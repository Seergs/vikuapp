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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.vikuPalette) private var palette
    @State private var presentation = AttachmentLoadingPresentation()
    @State private var presentationOrigin = ContinuousClock.now

    private var isLoading: Bool {
        viewModel.attachmentsLoadState == .idle || viewModel.attachmentsLoadState.isLoading
    }

    private var isWaiting: Bool {
        presentation.shouldWait(isLoading: isLoading)
    }

    var body: some View {
        SectionBlock(
            title: String(localized: "Attachments", bundle: .module),
            count: isWaiting || viewModel.attachments.isEmpty ? nil : "\(viewModel.attachments.count)",
            trailing: AnyView(
                SectionHeaderButton(title: String(localized: "Add", bundle: .module), action: onAdd)
                    .disabled(viewModel.isUploadingAttachment),
            ),
        ) {
            if isWaiting {
                HStack(spacing: VikuSpacing.sm) {
                    ProgressView()
                        .opacity(presentation.showsSpinner ? 1 : 0)
                        .accessibilityHidden(!presentation.showsSpinner)
                    Group {
                        if viewModel.isRetryingAttachments {
                            Text("Retrying…", bundle: .module)
                        } else {
                            Text("Loading attachments…", bundle: .module)
                        }
                    }
                    .font(VikuFont.subheadline)
                    .foregroundStyle(palette.textTertiary)
                    .opacity(presentation.showsSpinner || viewModel.isRetryingAttachments ? 1 : 0)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: VikuSpacing.xxl)
                .accessibilityHidden(!presentation.showsSpinner && !viewModel.isRetryingAttachments)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: presentation.showsSpinner)
                .transition(.identity)
            } else {
                AttachmentsList(
                    attachments: viewModel.attachments,
                    loadState: viewModel.attachmentsLoadState,
                    isUploading: viewModel.isUploadingAttachment,
                    notice: viewModel.attachmentsNotice,
                    canRetry: !viewModel.isRefreshingAttachments,
                    isRetrying: viewModel.isRetryingAttachments,
                    openingAttachmentID: viewModel.openingAttachmentID,
                    onOpen: onOpen,
                    onDelete: onDelete,
                    onRetry: { Task { await viewModel.retryAttachmentsDownload() } },
                )
                .transition(.identity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.attachments)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.attachmentsNotice)
            }
        }
        .task(id: isLoading) { await updatePresentation() }
        .onDisappear {
            presentation = AttachmentLoadingPresentation()
            presentationOrigin = .now
        }
    }

    private func updatePresentation() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let delay = presentation.update(
                isLoading: isLoading,
                at: presentationOrigin.duration(to: clock.now),
            )
            guard let delay else { return }
            do { try await clock.sleep(for: delay) } catch { return }
        }
    }
}

private struct AttachmentsList: View {
    let attachments: [TaskAttachment]
    let loadState: ScreenLoadState<Void>
    var isUploading = false
    let notice: String?
    let canRetry: Bool
    let isRetrying: Bool
    let openingAttachmentID: Int?
    let onOpen: (TaskAttachment) -> Void
    let onDelete: (TaskAttachment) -> Void

    let onRetry: () -> Void

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
                    .font(loadState.failureMessage == nil ? VikuFont.subheadline : VikuFont.caption)
                    .foregroundStyle(palette.textTertiary)
                if case .failure = loadState {
                    retryButton
                }
            } else {
                ForEach(attachments) { attachment in
                    AttachmentRow(
                        attachment: attachment,
                        isOpening: openingAttachmentID == attachment.id,
                        onOpen: { onOpen(attachment) },
                        onDelete: { onDelete(attachment) },
                    )
                    // Only the opening file changes appearance. The view model
                    // rejects concurrent opens without dimming unrelated rows.
                    .disabled(openingAttachmentID == attachment.id)
                }
            }

            if let notice {
                Text(verbatim: notice)
                    .font(VikuFont.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            if loadState == .loaded, notice != nil || isRetrying {
                retryButton
            }

            if isUploading {
                AttachmentUploadingRow()
            }
        }
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            if isRetrying {
                Text("Retrying…", bundle: .module)
            } else {
                Text("Retry", bundle: .module)
            }
        }
        .font(VikuFont.subheadline)
        .foregroundStyle(palette.brand)
        .disabled(!canRetry)
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
    let isOpening: Bool
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
                    Group {
                        if isOpening {
                            Text("Opening…", bundle: .module)
                        } else {
                            Text(verbatim: subtitle)
                        }
                    }
                    .font(VikuFont.caption)
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
