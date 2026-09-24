import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The "duplicate task" sheet, opened from a task's overflow menu
/// (`TaskDetailView`) or context menu (Today, a project's task list). Same
/// compact bottom-sheet language as `QuickAddSheetView` in Features/Tasks
/// (shared controls from `VikuDesignSystem`'s `TaskFormControls`),
/// pre-filled from the source task: an editable title (defaulting to
/// `"… (copy)"`), project, and priority, plus "Copy labels" / "Copy
/// relations" toggles when the source has either. Confirming creates the
/// duplicate, hands it back through `onDuplicated` (the host pushes its
/// detail screen), and dismisses. Lives in `VikuUI` rather than
/// `Features/Tasks` so every feature that lists tasks can offer it without
/// importing another feature.
public struct DuplicateTaskSheetView: View {
    @State private var viewModel: DuplicateTaskViewModel
    /// Called with the created task and its project right before the sheet
    /// dismisses, so the presenting screen can navigate to it. Optional — a
    /// caller that just wants the copy made can leave it off.
    private let onDuplicated: ((VikunjaTask, Project) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingProjectPicker = false
    @FocusState private var isTitleFocused: Bool

    /// A single content-sized detent, grown only for the copy toggles and
    /// the error banner — same reasoning as `QuickAddSheetView.detentHeight`.
    private var detentHeight: CGFloat {
        var height = Self.baseHeight
        if viewModel.hasLabelsToCopy {
            height += Self.toggleRowHeight
        }
        if viewModel.hasRelationsToCopy {
            height += Self.toggleRowHeight
        }
        if viewModel.saveErrorMessage != nil {
            height += Self.errorBannerHeight
        }
        return height
    }

    /// Takes a factory rather than an already-built view model: this sheet is
    /// presented from a host's `.sheet(isPresented:)`, whose content
    /// closure SwiftUI can re-invoke independently of this view's own
    /// identity (see `ConnectionsListView`'s `init` doc comment in Settings
    /// for the full mechanism — the same one that silently reset
    /// `TaskDetailView` itself before `AppDestinations.swift` got this
    /// treatment). Building the view model inside `@State`'s `init` means
    /// SwiftUI only uses `makeViewModel()`'s result the first time this
    /// sheet's identity is created, keeping that instance (and whatever the
    /// user has typed) across any later re-invocation.
    public init(
        makeViewModel: @escaping () -> DuplicateTaskViewModel,
        onDuplicated: ((VikunjaTask, Project) -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: makeViewModel())
        self.onDuplicated = onDuplicated
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VikuSpacing.md) {
                TextField("Task title", text: $viewModel.title)
                    .font(VikuFont.body)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                    .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                    .background(
                        VikuColor.Surface.field,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )

                projectSection

                PriorityChipRow(selection: $viewModel.priority)

                if viewModel.hasLabelsToCopy {
                    Toggle("Copy labels", isOn: $viewModel.copyLabels)
                        .font(VikuFont.subheadline)
                }
                if viewModel.hasRelationsToCopy {
                    Toggle("Copy relations", isOn: $viewModel.copyRelations)
                        .font(VikuFont.subheadline)
                }

                if let message = viewModel.saveErrorMessage {
                    SaveErrorBanner(message: message)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .tint(VikuColor.brandPrimary)
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.saveErrorMessage)
            .navigationTitle("Duplicate Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Duplicate") {
                            Task {
                                if let result = await viewModel.duplicate() {
                                    onDuplicated?(result.task, result.project)
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.bold)
                        .disabled(!viewModel.canSave)
                    }
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(
                title: "Choose Project",
                projects: viewModel.projects,
                selectedProjectID: viewModel.selectedProjectID,
            ) { project in
                viewModel.selectedProjectID = project?.id
            }
        }
        .task {
            isTitleFocused = true
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        switch viewModel.loadState {
        case let .failure(message):
            Text(message)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.textSecondary)
        case .loading, .idle:
            ProgressView()
        case .loaded:
            VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
                FieldLabel("Project")
                ProjectField(project: viewModel.selectedProject) {
                    isShowingProjectPicker = true
                }
            }
        }
    }

    private static let baseHeight: CGFloat = 300
    private static let toggleRowHeight: CGFloat = 44
    private static let errorBannerHeight: CGFloat = 66
}
