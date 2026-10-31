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
    @State private var confirmsServerReload = false
    @State private var requestsServerReload = false
    @State private var showsReloadIndicator = false
    @State private var reloadIndicatorShownAt: ContinuousClock.Instant?
    @State private var showsLoadingIndicator = false
    @State private var loadingIndicatorShownAt: ContinuousClock.Instant?
    @State private var pendingConflictRemoval: PendingSyncOperation?
    @State private var pendingTaskRemoval: PendingSyncOperation?
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.vikuIsOnline) private var isOnline

    init(makeViewModel: @escaping () -> PendingSyncViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    var body: some View {
        content
            .disabled(viewModel.isReloading || showsReloadIndicator)
            .confirmationDialog(
                Text("Discard local changes and reload?", bundle: .module),
                isPresented: $confirmsServerReload,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) {
                    requestsServerReload = true
                } label: { Text("Discard and reload", bundle: .module) }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: {
                Text(
                    // swiftlint:disable:next line_length
                    "All unsynced changes for this account will be lost, including local creations and changes without errors. Your local data and queue will stay unchanged if the download fails.",
                    bundle: .module,
                )
            }
            .task(id: requestsServerReload) {
                guard requestsServerReload else { return }
                await viewModel.reloadFromServer()
                requestsServerReload = false
            }
            .task(id: viewModel.isReloading) {
                await updateReloadIndicator()
            }
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
            .animation(rowAnimation, value: viewModel.isReloading)
            .animation(rowAnimation, value: showsOfflineBanner)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: showsReloadIndicator)
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
            if showsOfflineBanner {
                Section {
                    PendingSyncOfflineBanner(count: viewModel.presentation.operations.count)
                        .listRowBackground(palette.cardBackground)
                        .transition(rowTransition)
                }
            }
            if !viewModel.presentation.operations.isEmpty {
                Section {
                    ForEach(viewModel.presentation.operations) { operation in
                        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
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
                                    HStack(spacing: VikuSpacing.xxs) {
                                        Image(systemName: "ellipsis.circle")
                                        Text("Resolve", bundle: .module)
                                    }
                                }
                                .font(VikuFont.footnote)
                                .padding(.leading, VikuSpacing.xl + VikuSpacing.sm + VikuSpacing.xxs)
                                .padding(.top, VikuSpacing.xxs)
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
                    HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.sm) {
                        HStack(spacing: VikuSpacing.xxs) {
                            Text("Queued", bundle: .module)
                            Text(verbatim: "·")
                                .foregroundStyle(palette.textTertiary)
                                .accessibilityHidden(true)
                            Text(viewModel.presentation.operations.count, format: .number)
                                .monospacedDigit()
                                .contentTransition(reduceMotion ? .opacity : .numericText())
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                        Text("Changes are sent in this order", bundle: .module)
                            .font(VikuFont.caption2)
                            .textCase(nil)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            if viewModel.canReloadFromServer || viewModel.isReloading || showsReloadIndicator {
                Section {
                    if viewModel.isReloading || showsReloadIndicator {
                        HStack(spacing: VikuSpacing.sm) {
                            if showsReloadIndicator {
                                ProgressView()
                            }
                            Text("Reloading from server…", bundle: .module)
                                .foregroundStyle(palette.textSecondary)
                        }
                    } else {
                        Button(role: .destructive) {
                            confirmsServerReload = true
                        } label: {
                            Text("Discard local changes and reload", bundle: .module)
                        }
                        .disabled(!isOnline || !viewModel.busyOperationIDs.isEmpty)
                    }
                } footer: {
                    Text(
                        "Replaces this account's local data with the server's data. Requires a connection.",
                        bundle: .module,
                    )
                }
                .listRowBackground(palette.cardBackground)
            }
        }
        .settingsListStyle()
        .overlay {
            if viewModel.presentation.operations.isEmpty, !viewModel.isReloading, !showsReloadIndicator {
                PendingSyncEmptyState()
                    .padding(.top, VikuSpacing.xxl)
                    .transition(.opacity)
            }
        }
    }

    private var showsOfflineBanner: Bool {
        !isOnline && !viewModel.presentation.operations.isEmpty
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

    @MainActor
    private func updateReloadIndicator() async {
        do {
            if viewModel.isReloading {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                reloadIndicatorShownAt = .now
                showsReloadIndicator = true
            } else if let shownAt = reloadIndicatorShownAt {
                try await ContinuousClock().sleep(until: shownAt.advanced(by: .seconds(1)))
                try Task.checkCancellation()
                showsReloadIndicator = false
                reloadIndicatorShownAt = nil
            }
        } catch {
            // A fast reload or navigation cancels the pending presentation update.
        }
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

private struct PendingSyncEmptyState: View {
    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(spacing: VikuSpacing.sm) {
            Image(systemName: "checkmark")
                .font(VikuFont.title.weight(.bold))
                .foregroundStyle(palette.semanticSuccessText)
                .frame(width: VikuSpacing.xxl + VikuSpacing.md, height: VikuSpacing.xxl + VikuSpacing.md)
                .background(palette.semanticSuccess.opacity(0.15), in: Circle())
                .padding(.bottom, VikuSpacing.xs)
                .accessibilityHidden(true)

            Text("All caught up", bundle: .module)
                .font(VikuFont.headline)

            Text("Changes you make offline will appear here until they upload.", bundle: .module)
                .font(VikuFont.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .padding(VikuSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown above the queue while the device is offline: the queued changes are
/// safe on this device and will upload on their own once a connection returns.
private struct PendingSyncOfflineBanner: View {
    let count: Int

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.md) {
            HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                Image(systemName: "wifi.slash")
                    .font(VikuFont.body)
                    .foregroundStyle(palette.brand)
                    .frame(width: VikuSpacing.xl, height: VikuSpacing.xl)
                    .background(palette.brand.opacity(0.1), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    Text("You're offline", bundle: .module)
                        .font(VikuFont.headline)
                        .foregroundStyle(palette.textPrimary)

                    Text("\(count) changes saved on this iPhone. They'll be sent automatically when you're back online.", bundle: .module)
                        .font(VikuFont.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Label {
                Text("Waiting for connection", bundle: .module)
            } icon: {
                Image(systemName: "clock")
            }
            .font(VikuFont.subheadline.weight(.medium))
            .foregroundStyle(palette.brand)
            .padding(VikuSpacing.md)
            .frame(maxWidth: .infinity)
            .background(
                palette.brand.opacity(0.1),
                in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
            )
        }
        .padding(.vertical, VikuSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// Identifies what a queued change does at a glance. Failed items keep the
/// action glyph and signal the failure through color and the status label.
private struct PendingSyncOperationRow: View {
    let operation: PendingSyncOperation

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Image(systemName: operation.action.symbolName)
                .font(VikuFont.body)
                .foregroundStyle(statusColor)
                .frame(width: VikuSpacing.xl, height: VikuSpacing.xl)
                .background(
                    statusColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                )
                .contentTransition(.opacity)

            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                HStack(alignment: .top, spacing: VikuSpacing.sm) {
                    title
                    Spacer(minLength: 0)
                    Text(statusLabel, bundle: .module)
                        .font(VikuFont.caption)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, VikuSpacing.sm)
                        .padding(.vertical, VikuSpacing.xs)
                        .background(statusColor.opacity(0.1), in: Capsule())
                        .contentTransition(.opacity)
                }

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(operation.createdAt, format: .relative(presentation: .named))
                    .font(VikuFont.caption)
                    .foregroundStyle(palette.textTertiary)
            }
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

private extension PendingSyncAction {
    var symbolName: String {
        switch self {
        case .create: "plus"
        case .update: "pencil"
        case .moveBucket: "arrow.left.arrow.right"
        case .delete: "trash"
        case .addLabel: "tag"
        case .removeLabel: "tag.slash"
        case .addRelation: "link.badge.plus"
        case .removeRelation: "link"
        }
    }
}
