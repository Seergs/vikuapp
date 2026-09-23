import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The "new project" sheet: title, color, and parent project — matching what
/// `CreateProjectViewModel` needs to create a project. Same shape as `Tasks`'
/// `QuickAddSheetView`: a compact bottom sheet whose `NavigationStack` carries
/// an inline title and `Cancel`/`Save` in the toolbar, on a single detent
/// sized to its content so the keyboard doesn't stretch it. Presented as a
/// plain `.sheet` by whichever screen owns the trigger (`ProjectsView`'s
/// toolbar button, today).
public struct CreateProjectSheetView: View {
    @State private var viewModel: CreateProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    @State private var isShowingParentPicker = false

    /// A single detent sized to the current content — see
    /// `QuickAddSheetView.detentHeight` for why a two-detent set stretches
    /// under the keyboard.
    private var detentHeight: CGFloat {
        viewModel.saveErrorMessage != nil ? Self.expandedHeight : Self.compactHeight
    }

    /// Takes a factory rather than an already-built view model — see
    /// `EditProjectSheetView.init`'s doc comment for why.
    public init(makeViewModel: @escaping () -> CreateProjectViewModel) {
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
            .navigationTitle("New Project")
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
            ) { project in
                viewModel.parentProjectID = project?.id
            }
        }
        .task {
            if viewModel.hexColor.isEmpty {
                viewModel.hexColor = Self.colorSwatches[0]
            }
            await viewModel.load()
            isTitleFocused = true
        }
    }

    /// The color dot mirrors the swatch currently picked in `colorSection`,
    /// so the field itself previews what the project's swatch will look like
    /// (matching `ProjectRow`'s own color dot in the list) rather than only
    /// showing that choice further down the sheet.
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
                                // A soft halo in the swatch's own color rather
                                // than a hard dark ring — reads as "selected"
                                // without fighting the swatch for attention.
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

/// Same tinted-card language as `Tasks`' `QuickAddSheetView.SaveErrorBanner` —
/// duplicated rather than shared since neither package depends on the other
/// and the design system has no reusable banner component yet.
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

/// The collapsed "Parent Project" row: shows the current selection, or
/// "None" (a root-level project, the default) — unlike `QuickAddSheetView`'s
/// `ProjectField`, `nil` here is a real, already-made choice rather than a
/// placeholder for one still pending.
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
