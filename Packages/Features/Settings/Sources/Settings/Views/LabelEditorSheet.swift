import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The compact "new label" / "edit label" sheet: a title field and a row of
/// preset color swatches from `VikuColor.SwatchPalette.labelSwatches` — no
/// free-form color picker, matching how projects choose their color. Same shape as
/// `Projects`' `CreateProjectSheetView`: a `NavigationStack` carrying an
/// inline title and `Cancel`/`Save` in the toolbar, on a single detent sized
/// to its content so the keyboard doesn't stretch it.
struct LabelEditorSheet: View {
    let mode: LabelEditorMode
    /// Passed the trimmed title and the picked hex; the caller performs the
    /// create/update against the view model.
    let onSave: (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    @State private var title: String
    @State private var hexColor: String
    @State private var isSaving = false

    init(mode: LabelEditorMode, onSave: @escaping (String, String) async -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _hexColor = State(initialValue: VikuColor.SwatchPalette.labelSwatches[0])
        case let .edit(label):
            _title = State(initialValue: label.title)
            _hexColor = State(initialValue: label.hexColor)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VikuSpacing.md) {
                nameField
                colorSection
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(mode.isEdit ? "Edit Label" : "New Label")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .fontWeight(.bold)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .presentationDetents([.height(Self.detentHeight)])
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .task { isTitleFocused = true }
    }

    private var nameField: some View {
        HStack(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Circle()
                .fill(Color(vikuMutedHex: hexColor) ?? VikuColor.brandPrimary)
                .frame(width: 10, height: 10)

            TextField("Label name", text: $title)
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
            Text("Color")
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textSecondary)

            HStack(spacing: VikuSpacing.sm) {
                ForEach(VikuColor.SwatchPalette.labelSwatches, id: \.self) { swatch in
                    let swatchColor = Color(vikuHex: swatch) ?? VikuColor.brandPrimary
                    Circle()
                        .fill(swatchColor)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if swatch == hexColor {
                                Circle()
                                    .strokeBorder(swatchColor.opacity(0.35), lineWidth: 3)
                                    .padding(-4)
                            }
                        }
                        .onTapGesture { hexColor = swatch }
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = hexColor
        isSaving = true
        Task {
            await onSave(trimmed, color)
            isSaving = false
            dismiss()
        }
    }

    /// Shorter than `CreateProjectSheetView`'s 300: this sheet has one fewer
    /// row (no parent-project field), so 300 left a dead gap between the color
    /// swatches and the keyboard.
    private static let detentHeight: CGFloat = 236
}

private extension LabelEditorMode {
    var isEdit: Bool {
        if case .edit = self {
            return true
        }
        return false
    }
}
