import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// Lists the active account's queued mutations, oldest first, and updates
/// live as the queue drains. Conflicted rows can be removed; retrying a
/// failed push stays automatic for now.
struct PendingSyncView: View {
    @State private var viewModel: PendingSyncViewModel
    @State private var reloadID = 0
    @State private var pendingConflictRemoval: PendingSyncOperation?
    @Environment(\.vikuPalette) private var palette

    init(makeViewModel: @escaping () -> PendingSyncViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.pageBackground)
            .navigationTitle(Text("Pending Sync", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task(id: reloadID) {
                await viewModel.observe()
            }
            .confirmationDialog(
                Text("Remove this conflict?", bundle: .module),
                isPresented: Binding(get: { pendingConflictRemoval != nil }, set: {
                    if !$0 {
                        pendingConflictRemoval = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: pendingConflictRemoval,
            ) { (operation: PendingSyncOperation) in
                Button(role: .destructive) {
                    Task { await viewModel.discard(operation) }
                } label: {
                    Text("Remove Conflict", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { (_: PendingSyncOperation) in
                Text(
                    "This conflict was already discarded. Removing it only clears it from this list.",
                    bundle: .module,
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Couldn't load pending changes", bundle: .module),
                message: message,
            ) {
                reloadID += 1
            }
            .padding(.top, VikuSpacing.xxl)
        case .loaded:
            if viewModel.operations.isEmpty {
                VikuStatusView(
                    systemImage: "checkmark.circle",
                    title: String(localized: "Nothing waiting to sync", bundle: .module),
                    message: String(
                        localized: "Changes you make offline will appear here until they upload.",
                        bundle: .module,
                    ),
                )
                .padding(.top, VikuSpacing.xxl)
            } else {
                List {
                    Section {
                        ForEach(viewModel.operations) { operation in
                            PendingSyncOperationRow(operation: operation)
                                .listRowBackground(palette.cardBackground)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if operation.needsConflictResolution, operation.failureMessage == nil {
                                        Button(
                                            String(localized: "Remove Conflict", bundle: .module),
                                            systemImage: "trash",
                                            role: .destructive,
                                        ) {
                                            pendingConflictRemoval = operation
                                        }
                                        .tint(palette.semanticDanger)
                                    }
                                }
                        }
                    } header: {
                        Text("Waiting to upload", bundle: .module)
                    }
                }
                .settingsListStyle()
            }
        }
    }
}

private struct PendingSyncOperationRow: View {
    let operation: PendingSyncOperation

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Image(systemName: symbolName)
                .font(VikuFont.body)
                .foregroundStyle(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                title

                HStack(spacing: VikuSpacing.xxs) {
                    Text(operation.entity.displayName, bundle: .module)
                    Text(verbatim: "·")
                    Text(operation.action.displayName, bundle: .module)
                }
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textSecondary)

                if let message = operation.failureMessage {
                    Text(verbatim: message)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.semanticDangerText)
                }

                Text(operation.createdAt, format: .relative(presentation: .named))
                    .font(VikuFont.caption)
                    .foregroundStyle(palette.textTertiary)
            }

            Spacer(minLength: 0)

            Text(statusLabel, bundle: .module)
                .font(VikuFont.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, VikuSpacing.xxs)
    }

    @ViewBuilder
    private var title: some View {
        if let targetTitle = operation.targetTitle {
            Text(verbatim: targetTitle)
                .font(VikuFont.body)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
        } else {
            Text(operation.entity.displayName, bundle: .module)
                .font(VikuFont.body)
                .foregroundStyle(Color.primary)
        }
    }

    private var symbolName: String {
        operation.status == .failed ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath"
    }

    private var statusColor: Color {
        operation.status == .failed ? palette.semanticDangerText : palette.textSecondary
    }

    private var statusLabel: LocalizedStringKey {
        if operation.needsConflictResolution, operation.failureMessage == nil {
            "Conflict"
        } else if operation.status == .failed {
            "Failed"
        } else {
            "Waiting"
        }
    }
}

private extension PendingSyncEntity {
    var displayName: LocalizedStringKey {
        switch self {
        case .project: "Project"
        case .filter: "Saved Filter"
        case .label: "Label"
        case .task: "Task"
        case .comment: "Comment"
        }
    }
}

private extension PendingSyncAction {
    var displayName: LocalizedStringKey {
        switch self {
        case .create: "Created"
        case .update: "Updated"
        case .delete: "Deleted"
        case .addLabel: "Added label"
        case .removeLabel: "Removed label"
        case .addRelation: "Added relation"
        case .removeRelation: "Removed relation"
        }
    }
}
