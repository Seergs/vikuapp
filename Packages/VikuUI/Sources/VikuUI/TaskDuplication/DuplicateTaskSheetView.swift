import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Presents a pre-filled task composer from any feature that offers duplication.
public struct DuplicateTaskSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vikuPalette) private var palette
    @FocusState private var isTitleFocused: Bool
    @State private var viewModel: DuplicateTaskViewModel
    @State private var submission = TaskComposerSubmission()
    @State private var isShowingProjectPicker = false
    @State private var projectLoadAttempt = 0

    private let onDuplicated: ((VikunjaTask, Project) -> Void)?

    public init(
        makeViewModel: @escaping () -> DuplicateTaskViewModel,
        onDuplicated: ((VikunjaTask, Project) -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: makeViewModel())
        self.onDuplicated = onDuplicated
    }

    public var body: some View {
        TaskComposerSheet(submission: submission) {
            TextField(String(localized: "Task title", bundle: .module), text: $viewModel.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(VikuFont.title3)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1 ... 3)
                .focused($isTitleFocused)
                .disabled(submission.isSubmitting)
                .accessibilityIdentifier("duplicateTask.title")

            actions

            if viewModel.hasLabelsToCopy || viewModel.hasRelationsToCopy {
                copyOptions
            }

            if case let .failure(message) = viewModel.loadState {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    Text(verbatim: message)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Button(String(localized: "Retry", bundle: .module)) {
                        projectLoadAttempt += 1
                    }
                    .disabled(submission.isSubmitting)
                }
            }

            if let message = viewModel.saveErrorMessage {
                SaveErrorBanner(message: message)
            }
        }
        .tint(palette.brand)
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(
                title: String(localized: "Choose Project", bundle: .module),
                projects: viewModel.projects,
                selectedProjectID: viewModel.selectedProjectID,
            ) { project in
                viewModel.selectedProjectID = project?.id
            }
            .vikuNativeSheetAppearance()
        }
        .task { isTitleFocused = true }
        .task(id: projectLoadAttempt) { await viewModel.load() }
    }

    private var actions: some View {
        TaskComposerActions(
            submission: submission,
            canSubmit: viewModel.canSave,
            submitIcon: "checkmark",
            submitLabel: Text("Duplicate Task", bundle: .module),
            submitIdentifier: "duplicateTask.submit",
            submit: {
                guard viewModel.canSave else { return }
                submission.submit(
                    operation: { await viewModel.duplicate() },
                    onSuccess: { result in
                        onDuplicated?(result.task, result.project)
                        dismiss()
                    },
                )
            },
            fields: {
                TaskComposerProjectButton(project: viewModel.selectedProject) { isShowingProjectPicker = true }
                    .disabled(viewModel.projects.isEmpty)
                    .accessibilityIdentifier("duplicateTask.project")
                TaskComposerPriorityMenu(priority: viewModel.priority) { viewModel.priority = $0 }
            },
        )
    }

    private var copyOptions: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            if viewModel.hasLabelsToCopy {
                Toggle("Copy labels", isOn: $viewModel.copyLabels)
            }
            if viewModel.hasRelationsToCopy {
                Toggle("Copy relations", isOn: $viewModel.copyRelations)
            }
        }
        .font(VikuFont.subheadline)
        .disabled(submission.isSubmitting)
    }
}
