import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// Lists the active account's queued mutations, oldest first, and updates
/// live as the queue drains. Confirmed Kanban rejections expose recovery
/// actions; other conflicts keep their existing cleanup.
struct PendingSyncView: View {
    @State private var viewModel: PendingSyncViewModel
    @State private var reloadID = 0
    @State private var showsLoadingIndicator = false
    @State private var loadingIndicatorShownAt: ContinuousClock.Instant?
    @State private var pendingConflictRemoval: PendingSyncOperation?
    @State private var pendingTaskRemoval: PendingSyncOperation?
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(makeViewModel: @escaping () -> PendingSyncViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    var body: some View {
        content
            .confirmationDialog(
                Text("Choose a column", bundle: .module),
                isPresented: Binding(get: { viewModel.recoveryOperation != nil }, set: {
                    if !$0 {
                        viewModel.recoveryOperation = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: viewModel.recoveryOperation,
            ) { operation in
                ForEach(viewModel.recoveryBuckets) { bucket in
                    Button {
                        Task { await viewModel.retryCreation(operation, bucketID: bucket.id) }
                    } label: {
                        Text(verbatim: bucket.title)
                    }
                    .disabled(bucket.isFull)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            }
            .confirmationDialog(
                Text("Delete this local task?", bundle: .module),
                isPresented: Binding(get: { pendingTaskRemoval != nil }, set: {
                    if !$0 {
                        pendingTaskRemoval = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: pendingTaskRemoval,
            ) { operation in
                Button(role: .destructive) {
                    Task { await viewModel.deleteRejectedCreation(operation) }
                } label: { Text("Delete task", bundle: .module) }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: { _ in
                Text("This task was not created on the server. Its local changes will be deleted.", bundle: .module)
            }
            .animation(rowAnimation, value: viewModel.presentation.operations)
            .animation(.easeInOut(duration: 0.3), value: showsLoadingIndicator)
            .scrollContentBackground(.hidden)
            .background(palette.pageBackground)
            .navigationTitle(Text("Pending Sync", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task(id: reloadID) {
                await viewModel.observe()
            }
            .task(id: nextPresentationUpdate) {
                guard nextPresentationUpdate != nil else { return }
                await viewModel.advancePresentation()
            }
            .task(id: viewModel.loadState.isLoading) {
                await updateLoadingIndicator()
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
        if showsLoadingIndicator || viewModel.loadState.isLoading || viewModel.loadState == .idle {
            ZStack {
                palette.pageBackground
                if showsLoadingIndicator {
                    ProgressView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case let .failure(message) = viewModel.loadState {
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Couldn't load pending changes", bundle: .module),
                message: message,
            ) {
                reloadID += 1
            }
            .padding(.top, VikuSpacing.xxl)
        } else {
            queueList
        }
    }

    private var queueList: some View {
        List {
            if !viewModel.presentation.operations.isEmpty {
                Section {
                    ForEach(viewModel.presentation.operations) { operation in
                        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                            PendingSyncOperationRow(operation: operation)
                            if viewModel.canRecover(operation) {
                                Menu {
                                    Button {
                                        Task { await viewModel.retryCreation(operation) }
                                    } label: { Text("Retry", bundle: .module) }
                                    Button {
                                        Task { await viewModel.chooseRecoveryBucket(for: operation) }
                                    } label: { Text("Choose another column", bundle: .module) }
                                    Button(role: .destructive) {
                                        pendingTaskRemoval = operation
                                    } label: { Text("Delete task", bundle: .module) }
                                } label: {
                                    Label {
                                        Text("Resolve", bundle: .module)
                                    } icon: { Image(systemName: "ellipsis.circle") }
                                }
                                .font(VikuFont.footnote)
                                .disabled(viewModel.busyOperationIDs.contains(operation.id))
                            }
                        }
                        .listRowBackground(palette.cardBackground)
                        .transition(rowTransition)
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
                    HStack {
                        Text("Waiting to upload", bundle: .module)
                        Spacer()
                        Text(viewModel.presentation.operations.count, format: .number)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if viewModel.presentation.operations.isEmpty {
                VikuStatusView(
                    systemImage: "checkmark.circle",
                    title: String(localized: "Nothing waiting to sync", bundle: .module),
                    message: String(
                        localized: "Changes you make offline will appear here until they upload.",
                        bundle: .module,
                    ),
                )
                .padding(.top, VikuSpacing.xxl)
                .transition(.opacity)
            }
        }
    }

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.3)
    }

    private var nextPresentationUpdate: ContinuousClock.Instant? {
        guard viewModel.loadState == .loaded, !showsLoadingIndicator else { return nil }
        return viewModel.presentation.nextUpdate
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity.combined(with: .scale(scale: 0.96)),
        )
    }

    /// Loading presentation has its own lifetime; the provider never waits for it.
    @MainActor
    private func updateLoadingIndicator() async {
        do {
            if viewModel.loadState.isLoading {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                loadingIndicatorShownAt = .now
                showsLoadingIndicator = true
            } else if let shownAt = loadingIndicatorShownAt {
                try await ContinuousClock().sleep(until: shownAt.advanced(by: .seconds(1)))
                try Task.checkCancellation()
                showsLoadingIndicator = false
                loadingIndicatorShownAt = nil
            }
        } catch {
            // A fast load or navigation cancels the pending presentation update.
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
                .frame(width: VikuSpacing.xl, height: VikuSpacing.xl)
                .background(statusColor.opacity(0.1), in: Circle())
                .contentTransition(.opacity)

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
                .padding(.horizontal, VikuSpacing.sm)
                .padding(.vertical, VikuSpacing.xs)
                .background(statusColor.opacity(0.1), in: Capsule())
                .contentTransition(.opacity)
        }
        .padding(.vertical, VikuSpacing.xxs)
    }

    @ViewBuilder
    private var title: some View {
        if let targetTitle = operation.targetTitle {
            Text(verbatim: targetTitle)
                .font(VikuFont.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
        } else {
            Text(operation.entity.displayName, bundle: .module)
                .font(VikuFont.body)
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var symbolName: String {
        operation.status == .failed ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath"
    }

    private var statusColor: Color {
        operation.status == .failed ? palette.semanticDangerText : palette.brand
    }

    private var statusLabel: LocalizedStringKey {
        if operation.canRecoverKanbanCreation {
            "Needs action"
        } else if operation.needsConflictResolution, operation.failureMessage == nil {
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
        case .moveBucket: "Moved column"
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
