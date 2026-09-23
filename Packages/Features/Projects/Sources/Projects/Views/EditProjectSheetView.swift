import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Edit an existing project's title, color, and parent — the same shape as
/// `CreateProjectSheetView` (`NavigationStack` + inline title + toolbar
/// `Cancel`/`Save`, single content-sized detent).
public struct EditProjectSheetView: View {
    @State private var viewModel: EditProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    @State private var isShowingParentPicker = false

    private var detentHeight: CGFloat {
        viewModel.saveErrorMessage != nil ? Self.expandedHeight : Self.compactHeight
    }

    /// Takes a factory rather than an already-built view model: this sheet is
    /// presented from three different `.sheet(item:)` call sites
    /// (`ProjectsRootView`, `ProjectOverviewRootView`, `ProjectsView`), each
    /// of whose content closures SwiftUI can re-invoke independently of this
    /// view's own identity (see `ConnectionsListView`'s `init` doc comment in
    /// Settings for the full mechanism). Building the view model inside
    /// `@State`'s `init` means SwiftUI only uses `makeViewModel()`'s result
    /// the first time this sheet's identity is created.
    public init(makeViewModel: @escaping () -> EditProjectViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VikuSpacing.md) {
                nameField

                colorSection

                parentProjectSection

                if let message = viewModel.saveErrorMessage {
                    SaveErrorBanner(message: message)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.saveErrorMessage)
            .navigationTitle("Edit Project")
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
                        Button("Save", action: save)
                            .fontWeight(.bold)
                            .disabled(!viewModel.canSave)
                    }
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .sheet(isPresented: $isShowingParentPicker) {
            ProjectPickerSheet(
                title: "Parent Project",
                projects: viewModel.projects,
                selectedProjectID: viewModel.parentProjectID,
                showsNoneOption: true,
                excludingSubtreeOf: viewModel.editingProjectID,
            ) { project in
                viewModel.parentProjectID = project?.id
            }
        }
        .task {
            isTitleFocused = true
            await viewModel.load()
        }
    }

    private var nameField: some View {
        HStack(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Circle()
                .fill(Color(vikuHex: viewModel.hexColor) ?? VikuColor.brandPrimary)
                .frame(width: 10, height: 10)

            TextField("Project name", text: $viewModel.title)
                .font(VikuFont.body)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit(save)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            FieldLabel("Color")
            HStack(spacing: VikuSpacing.sm) {
                ForEach(Self.colorSwatches, id: \.self) { swatch in
                    let swatchColor = Color(vikuHex: swatch) ?? VikuColor.brandPrimary
                    Circle()
                        .fill(swatchColor)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if swatch == viewModel.hexColor {
                                Circle()
                                    .strokeBorder(swatchColor.opacity(0.35), lineWidth: 3)
                                    .padding(-4)
                            }
                        }
                        .onTapGesture { viewModel.hexColor = swatch }
                }
            }
        }
    }

    private var parentProjectSection: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            FieldLabel("Parent Project")
            ParentProjectField(project: viewModel.selectedParentProject) {
                isShowingParentPicker = true
            }
        }
    }

    private func save() {
        guard viewModel.canSave else { return }
        Task {
            if await viewModel.save() != nil {
                dismiss()
            }
        }
    }

    private static let compactHeight: CGFloat = 300
    private static let expandedHeight: CGFloat = 366
    private static let colorSwatches = VikuColor.SwatchPalette.swatches
}

private struct ParentProjectField: View {
    let project: Project?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.sm) {
                if let project {
                    ProjectPickerIcon(hexColor: project.hexColor)
                    Text(project.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary)
                } else {
                    Text("None")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
            }
            .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SaveErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Text(message)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            VikuColor.Semantic.danger.opacity(0.12),
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}

private struct FieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(VikuFont.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(VikuColor.textSecondary)
    }
}
