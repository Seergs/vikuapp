import SwiftUI
import VikuDesignSystem

/// Rename a saved filter - a single text field, no color or parent project
/// (saved filters have neither server-side, see `FilterRepositoryProtocol`).
/// Same shape as `EditProjectSheetView` (`NavigationStack` + inline title +
/// toolbar Cancel/Save, single content-sized detent) minus everything that
/// doesn't apply here.
public struct RenameFilterSheetView: View {
    @State private var viewModel: RenameFilterViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vikuPalette) private var palette
    @FocusState private var isTitleFocused: Bool

    private var detentHeight: CGFloat {
        viewModel.saveErrorMessage != nil ? Self.expandedHeight : Self.compactHeight
    }

    /// Takes a factory rather than an already-built view model - mirrors
    /// `EditProjectSheetView.init`'s doc comment for why.
    public init(makeViewModel: @escaping () -> RenameFilterViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VikuSpacing.md) {
                nameField

                if let message = viewModel.saveErrorMessage {
                    SaveErrorBanner(message: message)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.pageBackground)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.saveErrorMessage)
            .navigationTitle(Text("Rename Filter", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save", bundle: .module), action: save)
                            .fontWeight(.bold)
                            .disabled(!viewModel.canSave)
                    }
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .task {
            isTitleFocused = true
        }
    }

    private var nameField: some View {
        TextField(String(localized: "Filter name", bundle: .module), text: $viewModel.title)
            .font(VikuFont.body)
            .focused($isTitleFocused)
            .submitLabel(.done)
            .onSubmit(save)
            .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
            .background(palette.fieldBackground, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }

    private func save() {
        guard viewModel.canSave else { return }
        Task {
            if await viewModel.save() {
                dismiss()
            }
        }
    }

    private static let compactHeight: CGFloat = 180
    private static let expandedHeight: CGFloat = 246
}

/// Duplicated from `EditProjectSheetView`'s own `SaveErrorBanner` rather than
/// shared - both are already small, file-private copies (see
/// `CreateProjectSheetView`'s identical duplication), and the design system
/// has no reusable banner component yet.
private struct SaveErrorBanner: View {
    let message: String

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(palette.semanticDangerText)
            Text(message)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(palette.semanticDangerText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.semanticDanger.opacity(0.12),
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}
