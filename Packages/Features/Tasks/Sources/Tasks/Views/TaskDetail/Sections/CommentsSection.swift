import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// The Comments section: the task's comment thread (oldest first, matching
/// Vikunja's order) plus the composer to post a new one. A failure loading
/// comments only replaces the "no comments yet" placeholder — the composer
/// stays available either way, matching the design mockup.
struct CommentsSection: View {
    @Bindable var viewModel: TaskDetailViewModel
    let onEdit: (TaskComment) -> Void
    let onDelete: (TaskComment) -> Void
    var isComposerFocused: FocusState<Bool>.Binding

    var body: some View {
        SectionBlock(
            title: String(localized: "Comments", bundle: .module),
            count: viewModel.comments.isEmpty ? nil : "\(viewModel.comments.count)",
        ) {
            CommentsList(
                comments: viewModel.comments,
                loadState: viewModel.commentsLoadState,
                onSubmit: { text in
                    Task { await viewModel.addComment(text) }
                },
                onEdit: onEdit,
                onDelete: onDelete,
                isComposerFocused: isComposerFocused,
            )
        }
    }
}

private struct CommentsList: View {
    let comments: [TaskComment]
    let loadState: ScreenLoadState<Void>
    let onSubmit: (String) -> Void
    let onEdit: (TaskComment) -> Void
    let onDelete: (TaskComment) -> Void
    var isComposerFocused: FocusState<Bool>.Binding
    @State private var draft = ""

    private var emptyStateMessage: String {
        if case let .failure(message) = loadState {
            return message
        }
        return String(localized: "No comments yet.", bundle: .module)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.md - VikuSpacing.xxs) {
            if comments.isEmpty {
                Text(verbatim: emptyStateMessage)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: VikuSpacing.md - VikuSpacing.xxs) {
                    ForEach(comments) { comment in
                        CommentRow(
                            comment: comment,
                            onEdit: { onEdit(comment) },
                            onDelete: { onDelete(comment) },
                        )
                    }
                }
            }

            CommentComposer(draft: $draft, isFocused: isComposerFocused) {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                draft = ""
                onSubmit(text)
            }
        }
    }
}

private struct CommentRow: View {
    let comment: TaskComment
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var displayName: String {
        let name = comment.author.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return comment.author.username
    }

    private var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm) {
            Circle()
                .fill(VikuColor.Surface.field)
                .frame(width: 30, height: 30)
                .overlay {
                    Text(verbatim: initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VikuColor.textSecondary)
                }

            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.xs) {
                    Text(verbatim: displayName)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(verbatim: RelativeTimeFormatter.string(for: comment.created))
                        .font(.system(size: 12))
                        .foregroundStyle(VikuColor.textTertiary)
                }
                RichTextView(html: comment.comment, baseFont: VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textSecondary)
            }
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(String(localized: "Edit Comment", bundle: .module), systemImage: "pencil", action: onEdit)
            // `role: .destructive` alone renders blue here, not red: the tab
            // bar's `.tint(VikuColor.brandPrimary)` leaks into the context
            // menu — an explicit `.tint` is what forces the red, mirroring
            // `ProjectTaskRow`'s context menu in `Features/Projects`.
            Button(
                String(localized: "Delete Comment", bundle: .module),
                systemImage: "trash",
                role: .destructive,
                action: onDelete,
            )
            .tint(VikuColor.Semantic.danger)
        }
    }
}

private struct CommentComposer: View {
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            TextField(String(localized: "Write a comment...", bundle: .module), text: $draft)
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .focused(isFocused)
                .padding(.leading, VikuSpacing.sm)
                .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)

            Button(action: onSubmit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canSubmit ? .white : VikuColor.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(canSubmit ? VikuColor.brandPrimary : VikuColor.Surface.field, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.trailing, VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.xxs)
        .background(VikuColor.Surface.card, in: Capsule())
    }
}
