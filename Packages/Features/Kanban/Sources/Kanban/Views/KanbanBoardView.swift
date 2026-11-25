import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// A single project's Kanban board: one horizontally scrolling column per
/// bucket, each holding that bucket's tasks as draggable cards.
///
/// Takes a plain closure for the one cross-feature push it needs
/// (`onSelectTask`), mirroring `ProjectOverviewView` — Kanban itself never
/// imports `VikuNavigation`'s `AppRoute` or touches `AppRouter` directly, so
/// the caller decides how opening a task's detail is routed.
///
/// No `navigationTitle`/toolbar of its own: this is meant to swap in as the
/// body of a screen that already has both (the List/Kanban toggle on a
/// project's overview), not to be a destination in its own right.
public struct KanbanBoardView: View {
    @Bindable var viewModel: KanbanBoardViewModel
    @Binding private var boardSelection: Int?
    /// Mirrors `ProjectOverviewView`'s own `filteredTasks`: narrows each
    /// bucket's cards to the in-flight search text, by title only, without
    /// touching `viewModel.buckets` itself so drag-to-move and the
    /// done-bucket lookups in `KanbanBoardViewModel` keep seeing every task.
    let searchText: String
    let onSelectTask: (VikunjaTask) -> Void
    private let onBoardResolved: ((Int?) -> Void)?
    private let taskContextMenu: (VikunjaTask) -> [ContextMenuItem]

    @State private var hasStarted = false
    @State private var loadingPresentation = KanbanLoadingPresentation()
    @State private var presentationOrigin = ContinuousClock.now
    @State private var showsLoadingInContent = false
    @State private var dropTarget = KanbanDropTarget()
    @State private var dragPresentation = CardDragPresentation()
    @Environment(\.vikuPalette) private var palette

    public init(
        viewModel: KanbanBoardViewModel,
        boardSelection: Binding<Int?> = .constant(nil),
        searchText: String = "",
        onSelectTask: @escaping (VikunjaTask) -> Void,
        onBoardResolved: ((Int?) -> Void)? = nil,
        taskContextMenu: @escaping (VikunjaTask) -> [ContextMenuItem],
    ) {
        self.viewModel = viewModel
        self._boardSelection = boardSelection
        self.searchText = searchText
        self.onSelectTask = onSelectTask
        self.onBoardResolved = onBoardResolved
        self.taskContextMenu = taskContextMenu
    }

    public var body: some View {
        // Keep a vertical scroll surface for navigation styling. Each column
        // owns its pull-to-refresh and card scrolling.
        GeometryReader { geometry in
            ScrollView {
                if viewModel.preferredViewID == boardSelection {
                    content
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .refreshable { await viewModel.refresh() }
        }
        .background(palette.pageBackground)
        .onDisappear {
            dropTarget.reset()
            dragPresentation.reset()
            loadingPresentation = KanbanLoadingPresentation()
            showsLoadingInContent = false
        }
        .onChange(of: viewModel.viewID) {
            dropTarget.reset()
            dragPresentation.reset()
        }
        .task(id: isWaitingForBoard) {
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let wasVisible = loadingPresentation.isVisible
                let delay = loadingPresentation.update(
                    isLoading: isWaitingForBoard, at: presentationOrigin.duration(to: clock.now),
                )
                if wasVisible != loadingPresentation.isVisible {
                    showsLoadingInContent = loadingPresentation.isVisible && !viewModel.hasSnapshot
                }
                guard let delay else { return }
                do { try await clock.sleep(for: delay) } catch { return }
            }
        }
        .task(id: boardSelection) {
            hasStarted = false
            await viewModel.start(preferredViewID: boardSelection)
            if !Task.isCancelled {
                hasStarted = true
            }
        }
        .task { await viewModel.observeLocalChanges() }
        .onChange(of: resolution) { _, resolution in
            switch resolution {
            case let .board(id): onBoardResolved?(id)
            case .empty: onBoardResolved?(nil)
            case nil: break
            }
        }
    }

    private enum BoardResolution: Equatable {
        case board(Int)
        case empty
    }

    private var resolution: BoardResolution? {
        guard hasStarted, !viewModel.isRefreshing, viewModel.preferredViewID == boardSelection else { return nil }
        if viewModel.boardCatalog?.isEmpty == true {
            return loadingPresentation.isVisible ? nil : .empty
        }
        return viewModel.viewID.map(BoardResolution.board)
    }

    private var isWaitingForBoard: Bool {
        viewModel.isLoading || viewModel.isRefreshing
    }

    private var content: some View {
        VStack(spacing: VikuSpacing.sm) {
            HStack {
                if let catalog = viewModel.boardCatalog, catalog.count > 1 {
                    boardPicker(catalog)
                }
                Spacer()
                if loadingPresentation.isVisible, !showsLoadingInContent {
                    ProgressView()
                }
                Button { Task { await viewModel.refresh() } } label: {
                    Label { Text("Refresh", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
                }
                .disabled(viewModel.isRefreshing || viewModel.needsProjectSync)
            }
            .padding(.horizontal, VikuSpacing.md)
            if showsLoadingInContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                loadedContent
            }
        }
    }

    private func boardPicker(_ catalog: [KanbanViewSummary]) -> some View {
        let currentID = viewModel.viewID ?? boardSelection
        let current = catalog.first { $0.id == currentID } ?? catalog[0]
        return Menu {
            Text("Kanban boards", bundle: .module)
            Picker(selection: Binding(get: { current.id }, set: { boardSelection = $0 })) {
                ForEach(catalog) { view in
                    boardTitle(view).tag(view.id)
                }
            } label: {
                Text("Kanban board", bundle: .module)
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: VikuSpacing.sm) {
                Image(systemName: "rectangle.split.3x1")
                    .accessibilityHidden(true)
                boardTitle(current)
                    .bold()
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(VikuFont.caption2.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .font(VikuFont.subheadline)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, VikuSpacing.md)
            .padding(.vertical, VikuSpacing.sm)
            .background(palette.fieldBackground, in: Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Kanban board", bundle: .module))
        .accessibilityValue(boardTitle(current))
        .accessibilityIdentifier("kanban.boardSelector")
    }

    private func boardTitle(_ view: KanbanViewSummary) -> Text {
        if view.title.isEmpty {
            Text("Untitled board", bundle: .module)
        } else {
            Text(verbatim: view.title)
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            Spacer().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Couldn't load this board", bundle: .module),
                message: message,
                retry: { Task { await viewModel.refresh() } },
            )
        case .loaded:
            if viewModel.boardCatalog?.isEmpty == true {
                if onBoardResolved == nil {
                    VikuStatusView(
                        systemImage: "rectangle.split.3x1",
                        title: String(localized: "No Kanban boards", bundle: .module),
                        message: String(localized: "Refresh to check for boards.", bundle: .module),
                        retry: { Task { await viewModel.refresh() } },
                    )
                }
            } else if !viewModel.hasSnapshot {
                VikuStatusView(
                    systemImage: "icloud.and.arrow.down",
                    title: String(localized: "Board unavailable", bundle: .module),
                    message: unavailableMessage,
                )
            } else if viewModel.buckets.isEmpty {
                VikuStatusView(
                    systemImage: "rectangle.split.3x1",
                    title: String(localized: "This board is empty", bundle: .module),
                    message: String(localized: "Refresh to check for columns.", bundle: .module),
                )
            } else {
                if !viewModel.supportsWrites {
                    Text("This board uses server rules. Use Vikunja's web app to make changes.", bundle: .module)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, VikuSpacing.md)
                }
                board.id(viewModel.viewID)
            }
        }
    }

    private var unavailableMessage: String {
        if viewModel.needsProjectSync {
            String(localized: "Sync this project before downloading its board.", bundle: .module)
        } else {
            String(localized: "Connect and refresh to download this board for offline use.", bundle: .module)
        }
    }

    private var board: some View {
        let activeViewID = viewModel.viewID
        return KanbanHorizontalScroll {
            HStack(alignment: .top, spacing: VikuSpacing.md) {
                ForEach(viewModel.buckets) { bucket in
                    KanbanColumnView(
                        bucket: bucket,
                        searchText: searchText,
                        dropTarget: $dropTarget,
                        dragPresentation: dragPresentation,
                        allowsMutations: viewModel.supportsWrites,
                        allowsTaskCreation: viewModel.supportsTaskCreation,
                        onRefresh: { await viewModel.refresh() },
                        onSelectTask: onSelectTask,
                        taskContextMenu: taskContextMenu,
                        onToggleDone: { task in
                            Task {
                                guard viewModel.viewID == activeViewID else { return }
                                await viewModel.toggleDone(task)
                            }
                        },
                        onDropTaskID: { taskID in
                            guard viewModel.viewID == activeViewID else { return false }
                            return await viewModel.moveTask(taskID: taskID, to: bucket)
                        },
                        onAddTask: { title in
                            guard viewModel.viewID == activeViewID else { return false }
                            return await viewModel.createTask(title: title, in: bucket)
                        },
                    )
                }
            }
            .padding(VikuSpacing.md)
            .scrollTargetLayout()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

#Preview {
    KanbanBoardView(
        viewModel: KanbanBoardViewModel(
            project: Project(id: 1, title: "Work"),
            repository: PreviewBucketRepository(),
            syncTrigger: PreviewScreenSync(), localData: PreviewScreenSync(),
            toastPresenter: PreviewToastPresenter(),
        ),
        onSelectTask: { _ in },
        taskContextMenu: { _ in [] },
    )
}

// MARK: - Preview Helpers

private actor PreviewBucketRepository: KanbanBoardRepositoryProtocol {
    func hasCachedKanbanSupport() async throws -> Bool {
        true
    }

    func fetchBoard(projectID: EntityID, viewID: Int?) async throws -> KanbanBoardSnapshot {
        .available(KanbanBoard(viewID: 1, buckets: [
            KanbanBucket(
                id: 1, title: "To Do", tasks: [VikunjaTask(id: 1, title: "Write proposal", projectID: projectID)],
            ),
            KanbanBucket(id: 2, title: "Done", isDoneBucket: true),
        ], defaultBucketID: 1, supportsWrites: true, lastPulledAt: Date()))
    }

    func createTask(title: String, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask {
        VikunjaTask(id: .local(UUID()), title: title, projectID: projectID)
    }

    func setCompletion(
        taskID: EntityID, projectID: EntityID, viewID: Int, isDone: Bool,
    ) async throws -> VikunjaTask {
        throw VikunjaError.notFound
    }

    func moveTask(taskID: EntityID, projectID: EntityID, viewID: Int, bucketID: Int) async throws -> VikunjaTask {
        VikunjaTask(id: taskID, title: "Write proposal", isDone: bucketID == 2, projectID: projectID)
    }
}

private struct PreviewScreenSync: SyncTriggering, LocalDataObserving {
    func hasInitialSnapshot() async throws -> Bool {
        true
    }

    func prepare() async throws {}
    func refresh(scope: SyncScope) async throws {}
    func localChanges() async -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct PreviewToastPresenter: ToastPresenting {
    func show(_: String, style _: ToastStyle) {}
}
