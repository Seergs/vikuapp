import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Add/remove labels on the task, and create a new one on the fly — matches
/// the design mockup's label sheet. A `.searchable` list rather than a
/// custom text field; unlike the project picker, tapping a row here toggles
/// membership instead of dismissing, since a task can carry more than one
/// label.
struct LabelPickerSheet: View {
    @Bindable var viewModel: TaskDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pickedColor = VikuColor.SwatchPalette.swatches[0]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLabels: [VikunjaCore.Label] {
        guard !trimmedQuery.isEmpty else { return viewModel.allLabels }
        return viewModel.allLabels.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var hasExactMatch: Bool {
        viewModel.allLabels.contains { $0.title.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    ForEach(filteredLabels) { label in
                        LabelPickerRow(label: label, isSelected: viewModel.task.labels.contains(label)) {
                            Task { await viewModel.toggleLabel(label) }
                        }
                    }

                    if !trimmedQuery.isEmpty, !hasExactMatch {
                        CreateLabelCard(title: trimmedQuery, pickedColor: $pickedColor) {
                            let title = trimmedQuery
                            let color = pickedColor
                            query = ""
                            Task { await viewModel.createAndAddLabel(title: title, hexColor: color) }
                        }
                    }
                }
                .padding(.vertical, VikuSpacing.sm)
            }
            .searchable(text: $query, prompt: "Search or create label...")
            .navigationTitle("Labels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .task { await viewModel.loadAllLabels() }
    }
}

private struct LabelPickerRow: View {
    let label: VikunjaCore.Label
    let isSelected: Bool
    let action: () -> Void

    private var color: Color {
        Color(vikuHex: label.hexColor) ?? VikuColor.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(label.title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color.primary)
                Spacer()
                // An explicit checkbox rather than a checkmark that only
                // appears once selected — an empty circle makes it obvious
                // up front that rows are multi-select, not "pick one".
                LabelSelectionIndicator(isSelected: isSelected)
            }
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            .background(
                isSelected ? VikuColor.Surface.field : Color.clear,
                in: RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xxs, style: .continuous),
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VikuSpacing.sm)
    }
}

/// A quieter checkbox than `TaskDetailCheckbox` — a thin, low-opacity ring
/// that fills with a soft gray tint (not a solid color) and a muted
/// checkmark, matching the mockup's subtler treatment for "is this label
/// picked" versus the task's own bold completion toggle.
private struct LabelSelectionIndicator: View {
    let isSelected: Bool
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .strokeBorder(VikuColor.textTertiary.opacity(isSelected ? 0 : 0.4), lineWidth: 1.5)
            .background(Circle().fill(VikuColor.textTertiary.opacity(isSelected ? 0.22 : 0)))
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(VikuColor.textSecondary)
                }
            }
    }
}

/// Offered only once the search query doesn't match any existing label
/// exactly — lets the user pick a swatch from `VikuColor.SwatchPalette`
/// and create+attach the label in one tap.
private struct CreateLabelCard: View {
    let title: String
    @Binding var pickedColor: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Create New Label")
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textSecondary)

            HStack(spacing: VikuSpacing.sm) {
                Circle()
                    .fill(Color(vikuHex: pickedColor) ?? VikuColor.brandPrimary)
                    .frame(width: 12, height: 12)
                Text("\"\(title)\"")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }

            HStack(spacing: VikuSpacing.sm) {
                ForEach(VikuColor.SwatchPalette.swatches, id: \.self) { swatch in
                    Circle()
                        .fill(Color(vikuHex: swatch) ?? VikuColor.brandPrimary)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if swatch == pickedColor {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                        .onTapGesture { pickedColor = swatch }
                }
            }

            Button(action: action) {
                Text("Create and Add")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VikuSpacing.sm)
                    .background(
                        VikuColor.brandPrimary,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(VikuSpacing.md - VikuSpacing.xxs)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.top, VikuSpacing.xs)
    }
}
